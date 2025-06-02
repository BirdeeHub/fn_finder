return function(MAIN, _)
    local M = {}

    local dsep, psep, phold, errpre =
        MAIN.pkgConfig.dirsep, MAIN.pkgConfig.pathsep, MAIN.pkgConfig.pathmark, MAIN.pkgConfig.errpre
    local DEFAULT_FNL_PATH = "." .. dsep .. phold .. ".fnl" .. psep .. "." .. dsep .. phold .. dsep .. "init.fnl"

    local function rtpfile(dir, modname, patterns)
        dir = type(dir) == "string" and dir or "lua"
        modname = modname:gsub("%.", "/")
        patterns = patterns or {}
        local modpath
        local i = 1
        while not modpath do
            local pattern = patterns[i]
            if not pattern then
                break
            end
            modpath = vim.api.nvim_get_runtime_file(dir .. "/" .. modname .. pattern, false)[1]
            i = i + 1
        end
        return modpath
    end

    local function read_file(filename)
        local ok, file = pcall(io.open, filename, "r")
        if ok and file then
            local content = file:read("*a")
            file:close()
            return content
        end
        return nil, "Could not read file '" .. tostring(filename) .. "'"
    end

    ---@class fn_finder.FennelSearchOpts
    ---@field path? string|fun(modname: string, existing: string):(modpath: string)
    ---@field on_first_compile? fun(fennel: table, opts: fn_finder.FennelSearchOpts)
    ---@field compiler? table -- fennel compiler options
    ---@field nvim? boolean|string?

    ---@class fn_finder.FennelOpts : fn_finder.LoaderOpts
    ---@field search_opts? fn_finder.FennelSearchOpts

    ---@param loader_opts? fn_finder.FennelOpts
    ---@return fun(modname: string):function|string?
    M.mkFinder = function(loader_opts)
        loader_opts = loader_opts or {}
        local triggered = false
        local fennel = package.loaded["fennel"] or nil
        if type(fennel) ~= "table" then
            fennel = nil
        end
        if (loader_opts.search_opts or {}).nvim then
            loader_opts.cache_opts = loader_opts.cache_opts or {}
            loader_opts.cache_opts.cache_dir = loader_opts.cache_opts.cache_dir
                or (vim.fn.stdpath("cache") .. dsep .. "fn_finder_cache")
        end
        loader_opts.search = loader_opts.search
            or function(modname, opts)
                opts = opts or {}
                local pt = type(opts.path)
                local modpath
                if opts.nvim then
                    modpath = rtpfile(opts.nvim, modname, { ".fnl", "/init.fnl" })
                end
                if not modpath then
                    local p = (fennel or {}).path or DEFAULT_FNL_PATH
                    if pt == "function" then
                        modpath = opts.path(modname, p)
                    elseif pt == "string" then
                        modpath = MAIN.searchModule(modname, opts.path)
                    else
                        modpath = MAIN.searchModule(modname, p)
                    end
                end
                if not triggered and modpath then
                    triggered = true
                    local macro_searcher = function(n)
                        local mp = rtpfile(opts.nvim, n, { ".fnl", "/init.fnl", "/init-macros.fnl" })
                        if mp then
                            if not fennel then
                                local ok
                                ok, fennel = pcall(require, "fennel")
                                if not ok then
                                    fennel = nil
                                end
                            end
                            if fennel then
                                local ok, res = pcall(fennel.eval, read_file(mp), {
                                    ["module-name"] = n,
                                    filename = mp,
                                    env = "_COMPILER",
                                    requireAsInclude = false,
                                })
                                if ok then
                                    return function()
                                        return res
                                    end
                                end
                                return errpre
                                    .. "Could not load fennel macro module '"
                                    .. tostring(n)
                                    .. "' "
                                    .. tostring(res or mp)
                            end
                            return errpre .. "Could not load fennel to call macro module '" .. tostring(n) .. "'"
                        else
                            return errpre .. "Could not find macro for module name '" .. tostring(n) .. "'"
                        end
                    end
                    if type(fennel) == "table" then
                        if opts.nvim then
                            table.insert(fennel["macro-searchers"], macro_searcher)
                        end
                        if opts.on_first_compile then
                            opts.on_first_compile(fennel, opts)
                        end
                    else
                        local ok
                        ok, fennel = pcall(require, "fennel")
                        if not ok then
                            fennel = nil
                        else
                            if opts.nvim then
                                table.insert(fennel["macro-searchers"], macro_searcher)
                            end
                            if opts.on_first_compile then
                                opts.on_first_compile(fennel, opts)
                            end
                        end
                    end
                end
                if not modpath then
                    return nil,
                        nil,
                        errpre
                            .. "fn_finder fennel searcher could not find a fennel file for '"
                            .. tostring(modname)
                            .. "'"
                elseif not fennel then
                    return nil, nil, errpre .. "fn_finder fennel searcher cannot require('fennel')"
                end
                opts.compiler = opts.compiler or {}
                opts.compiler.filename = modpath
                local ok, lua_code = pcall(fennel.compileString, read_file(modpath), opts.compiler)
                if ok and lua_code then
                    return lua_code, modpath, nil
                else
                    return nil,
                        nil,
                        errpre
                            .. "fn_finder fennel search function could not find a valid fennel file for '"
                            .. tostring(modname)
                            .. "': "
                            .. tostring(lua_code or modpath)
                end
            end
        return MAIN.mkFinder(loader_opts)
    end

    ---@overload fun(opts: fn_finder.FennelOpts)
    ---@overload fun(pos: number, opts: fn_finder.FennelOpts)
    M.install = function(pos, opts)
        if type(pos) == "number" then
            table.insert(package.loaders or package.searchers, pos, M.mkFinder(opts or {}))
        else
            table.insert(package.loaders or package.searchers, M.mkFinder(pos or opts or {}))
        end
    end

    return M
end
