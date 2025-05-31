return function(MAIN)
    local M = {}

    local function read_file(filename)
        local ok, file = pcall(io.open, filename, "r")
        if ok and file then
            local content = file:read("*a")
            file:close()
            return content
        end
        return nil, file
    end

    ---@class fn_finder.FennelSearchOpts
    ---@field path? string|fun(modname: string, existing: string):(modpath: string)
    ---@field macro_path? string|fun(existing: string):(full_path: string)
    ---@field macro_searchers? (fun(modname: string):(function|string)?)[]|fun(modname: string):(function|string)?
    ---@field compiler? table -- fennel compiler options

    ---@class fn_finder.FennelOpts : fn_finder.LoaderOpts
    ---@field search_opts? fn_finder.FennelSearchOpts

    ---@param loader_opts? fn_finder.FennelOpts
    ---@return fun(modname: string):function|string?
    M.mkFinder = function(loader_opts)
        loader_opts = loader_opts or {}
        loader_opts.search = loader_opts.search or function(modname, opts)
            local ok, fennel = pcall(require, "fennel")
            if not ok or not fennel then
                return nil, nil, "\n\tfn_finder fennel searcher cannot require('fennel')"
            end
            opts = opts or {}
            if opts.set_global then
                _G.fennel = fennel
            end
            if type(opts.macro_path) == "string" then
                fennel["macro-path"] = opts.macro_path
            elseif type(opts.macro_path) == "function" then
                fennel["macro-path"] = opts.macro_path(fennel["macro-path"])
            end
            if type(opts.macro_searchers) == "function" then
                table.insert(fennel["macro-searchers"], opts.macro_searchers)
            elseif type(opts.macro_searchers) == "table" then
                for _, v in ipairs(opts.macro_searchers or {}) do
                    table.insert(fennel["macro-searchers"], v)
                end
            end
            local pt = type(opts.path)
            local modpath
            if pt == "function" then modpath = opts.path(modname, fennel.path)
            elseif pt == "string" then modpath = MAIN.searchModule(modname, opts.path)
            else modpath = MAIN.searchModule(modname, fennel.path) end
            opts.filename = modpath
            local lua_code
            ok, lua_code = pcall(fennel.compileString, read_file(modpath), opts.compiler or {})
            if ok and lua_code then
                return lua_code, modpath, nil
            else
                return nil, nil,
                    "\n\tfn_finder fennel search function could not find a valid fennel file for '" ..
                    modname .. "': " .. tostring(lua_code or modpath)
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
