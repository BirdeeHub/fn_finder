local M = {}

local _load = load

if load == nil then -- 5.1 compat
    _load = function(chunk, chunkname, _, env)
        if type(chunk) == "function" then
            local res = chunk()
            local function i()
                local v = chunk()
                res = res .. (v or "")
                return v
            end
            while i() do end
            chunk = res
        end
        local f, err = loadstring(chunk, chunkname)
        if not f then return nil, err end
        if env then setfenv(f, env) end
        return f
    end
end

-- have searchModule use package.config to process package.path (windows compat)
local cfg = string.gmatch(package.config, "([^\n]+)")
local dirsep, pathsep, pathmark = cfg() or '/', cfg() or ';', cfg() or '?'

local function write_file(filename, content)
    local ok, file = pcall(io.open, filename, "w")
    if ok and file then
        file:write(content)
        file:close()
        return true
    end
    return false
end

local function read_file(filename)
    local ok, file = pcall(io.open, filename, "r")
    if ok and file then
        local content = file:read("*a")
        file:close()
        return content
    end
    return nil, file
end

local function simple_table_hash(input)
    local ok_types = {
        number = true, string = true, boolean = true, ["nil"] = true,
    }
    local visited = {}
    local cerealize -- hehe... ignore the breakfast pun, this hash is only lightly scrambled
    local function valstr(v)
        local t = type(v)
        if ok_types[t] then
            return tostring(v)
        elseif t == "table" then
            if visited[v] then
                return visited[v]
            else
                local val = cerealize(v)
                visited[v] = val
                return val
            end
        else
            return t -- type name if non-deterministic
        end
    end
    cerealize = function(tbl)
        local keys = {}
        for k in pairs(tbl) do table.insert(keys, k) end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local acc = ""
        for _, k in ipairs(keys) do
            acc = acc .. valstr(k) .. "=" .. valstr(tbl[k]) .. ","
        end
        return acc
    end
    local res = cerealize(input)
    local hash = 0
    for i = 1, #res do
        hash = (hash * 31 + res:byte(i)) % 2 ^ 32
    end
    return hash
end

---@class fn_finder.FileAttrs
---@field mtime number
---@field ctime number
---@field size number

---@param modpath string
---@return fn_finder.FileAttrs?
local function get_file_meta(modpath)
    local uv = (vim or {}).uv or (vim or {}).loop
    if not uv then
        local ok, err = pcall(require, "luv")
        if ok then uv = err end
    end
    local err = nil
    local mtime
    local ctime
    local size
    if uv then
        local stat
        stat, err = uv.fs_stat(modpath)
        if stat then
            mtime = stat.mtime.sec
            ctime = stat.ctime.sec
            size = stat.size
        end
    else
        local ok, lfs = pcall(require, "lfs")
        if ok then
            mtime, err = lfs.attributes(modpath, "modification")
            ctime, err = lfs.attributes(modpath, "change")
            size, err = lfs.attributes(modpath, "size")
        else
            err = "fn_finder default fs_lib setting requires uv or lfs"
        end
    end
    if not err and mtime and ctime and size then
        return { mtime = mtime, ctime = ctime, size = size }
    else
        return nil
    end
end

---@class fn_finder.Meta: fn_finder.FileAttrs
---@field modname string
---@field modpath string
---@field opts_hash number

---@param modname string
---@param cache_opts table
---@return nil|string|fun():string? chunk
---@return fn_finder.Meta?
local default_fetch = function(modname, cache_opts)
    local contents, err = read_file((cache_opts.cache_dir or "/tmp/fn_finder_cache") .. dirsep .. modname)
    if err or not contents then return nil, nil end
    local zero = contents:find('\0', 1, true) -- plain find
    if not zero then return nil, nil end
    local header_str = contents:sub(1, zero - 1)
    local chunk = contents:sub(zero + 1)
    local fields = {}
    for field in (header_str .. ";"):gmatch("([^;]*);") do
        table.insert(fields, field)
    end
    if #fields < 6 then return nil, nil end
    return chunk, {
        modname = fields[1],
        modpath = fields[2],
        opts_hash = tonumber(fields[3]),
        mtime = tonumber(fields[4]),
        ctime = tonumber(fields[5]),
        size = tonumber(fields[6]),
    }
end

---@param chunk string
---@param meta fn_finder.Meta
---@param cache_opts table
local function cache_chunk(chunk, meta, cache_opts)
    local mkdir = cache_opts.mkdir or function(p)
        local uv = (vim or {}).uv or (vim or {}).loop
        if not uv then
            local ok, err = pcall(require, "luv")
            if ok then
                uv = err
            end
        end
        if uv then
            uv.fs_mkdir(p, 493)
        else
            local ok, lfs = pcall(require, "lfs")
            if ok then
                lfs.mkdir(p)
            end
        end
    end
    local dir = cache_opts.cache_dir or "/tmp/fn_finder_cache"
    mkdir(dir)
    local header = { meta.modname, meta.modpath, meta.opts_hash, meta.mtime, meta.ctime, meta.size }
    ---@diagnostic disable-next-line: cast-local-type
    write_file(dir .. dirsep .. meta.modname, table.concat(header, ';') .. '\0' .. chunk)
end

local function meta_eq(m1, m2)
    return m1.modpath == m2.modpath and m1.modname == m2.modname and m1.mtime == m2.mtime
        and m1.ctime == m2.ctime and m1.size == m2.size
        and m1.opts_hash == m2.opts_hash
end

---@param modname string
---@param opts_hash number
---@param loader_opts fn_finder.LoaderOpts
---@return nil|string|fun():string? chunk
---@return string? modpath
local function fetch_cached(modname, opts_hash, loader_opts)
    local chunk, meta = (loader_opts.get_cached or default_fetch)(modname, loader_opts.cache_opts or {})
    if not chunk or not meta then
        return nil, nil
    end
    if loader_opts.auto_invalidate then
        local m2 = loader_opts.fs_lib and loader_opts.fs_lib(meta.modpath) or get_file_meta(meta.modpath)
        if m2 then
            ---@cast m2 fn_finder.Meta
            m2.modpath = meta.modpath
            m2.modname = modname
            m2.opts_hash = opts_hash
            if meta_eq(meta, m2) then
                return chunk, meta.modpath
            end
        end
    else
        if opts_hash == meta.opts_hash and meta.modpath then
            return chunk, meta.modpath
        end
    end
    return nil, nil
end

---@class fn_finder.LoaderOpts
---@field search_opts? table
---@field cache_opts? table
---@field strip? boolean
---@field env? table
---@field auto_invalidate? boolean
---Attention: if search returns a chunk, it must also return its modpath
---alternatively, you may fetch the meta class yourself and return a function representing the module.
---@field search? string|fun(n: string, search_opts: table, opts_hash: number, env?: table):(chunk: nil|string|fun():(string|any)?, modpath: (string|fn_finder.Meta)?, err: string?)
---Attention: if get_cached returns a chunk, it must also return meta
---@field get_cached? fun(modname: string, cache_opts: table):(chunk: nil|string|fun():string?, meta: fn_finder.Meta)
---@field cache_chunk? fun(chunk: string, meta: fn_finder.Meta, cache_opts: table)
---@field fs_lib? fun(modname: string):fn_finder.FileAttrs?

---@param loader_opts? fn_finder.LoaderOpts
---@return fun(modname: string):function|string?
M.mkFinder = function(loader_opts)
    loader_opts = loader_opts or {}
    loader_opts.auto_invalidate = loader_opts.auto_invalidate ~= false
    local opts_hash = simple_table_hash {
        VERSION = _VERSION,
        loader_opts = loader_opts,
    }
    return function(modname)
        local chunk, modpath, err = fetch_cached(modname, opts_hash, loader_opts)
        local mkmsg = function(n, e)
            return "\n\tModule not found: '" .. n .. "'" .. (e and (" " .. tostring(e)) or "")
        end
        if modpath and chunk then
            chunk, err = _load(chunk, "@" .. modpath, "b", loader_opts.env)
            return chunk or mkmsg(modname, err)
        else
            local spath = loader_opts.search or package.path
            if type(spath) == "function" then
                ---@diagnostic disable-next-line: cast-local-type
                chunk, modpath, err = spath(modname, loader_opts.search_opts or {}, opts_hash, loader_opts.env)
            else
                modpath = M.searchModule(modname, spath)
                chunk, err = read_file(modpath)
            end
            if modpath and chunk then
                if type(modpath) == "table" then
                    ---@diagnostic disable-next-line: cast-type-mismatch
                    ---@cast modpath fn_finder.Meta
                    local meta = modpath
                    local ok, compiled = pcall(string.dump, chunk, loader_opts.strip)
                    if ok then
                        local cacher = loader_opts.cache_chunk or cache_chunk
                        cacher(compiled, meta, loader_opts.cache_opts or {})
                    end
                    return chunk
                else
                    ---@cast modpath string
                    chunk, err = _load(chunk, "@" .. modpath, "t", loader_opts.env)
                    if chunk then
                        local ok, compiled = pcall(string.dump, chunk, loader_opts.strip)
                        local meta = loader_opts.fs_lib and loader_opts.fs_lib(modpath) or get_file_meta(modpath)
                        if ok and compiled and meta then
                            ---@cast meta fn_finder.Meta
                            meta.opts_hash = opts_hash
                            meta.modname = modname
                            meta.modpath = modpath
                            local cacher = loader_opts.cache_chunk or cache_chunk
                            cacher(compiled, meta, loader_opts.cache_opts or {})
                        end
                        return chunk
                    end
                end
            end
        end
        return mkmsg(modname, err)
    end
end

M.pkgConfig = { dirsep = dirsep, pathsep = pathsep, pathmark = pathmark }

-- Escape a string for safe use in a Lua pattern
function M.escapepat(str)
    return string.gsub(str, "[^%w]", "%%%1")
end

---@param modulename string
---@param pathstring string
---@return string? modpath
function M.searchModule(modulename, pathstring)
    local pathsepesc = M.escapepat(pathsep)
    local pathsplit = string.format("([^%s]*)%s", pathsepesc, pathsepesc)
    local nodotModule = modulename:gsub("%.", dirsep)
    for path in string.gmatch(pathstring .. pathsep, pathsplit) do
        local filename = path:gsub(M.escapepat(pathmark), nodotModule)
        local filename2 = path:gsub(M.escapepat(pathmark), modulename)
        local file = io.open(filename) or io.open(filename2)
        if file then
            file:close()
            return filename
        end
    end
end

local require_path = ...
return setmetatable(M, {
    __index = function(t, k)
        local res = require(require_path .. ".configs." .. k)(t)
        rawset(t, k, res)
        return res
    end,
})
