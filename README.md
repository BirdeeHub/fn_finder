# fnFinder Module Reference

- TODO: intro and basic useage here:

---

## 📦 Module: `fnFinder`

### `fnFinder.mkFinder(loader_opts?: fnFinder.LoaderOpts): (modname: string) -> string|function|nil`

The function that provides the core functionality of the `fnFinder` module.

Creates a module loader function suitable for use in `package.loaders` or `package.searchers`, supporting caching and file search customization.

#### Parameters:

* `loader_opts` (`fnFinder.LoaderOpts?`): Optional table of loader customization options.

##### `fnFinder.LoaderOpts`:

* `search`: Accepts one of the following forms:
    - `string`: the string to search as the `package.path` for your lua dialect
    - `fun(n: string, search_opts: table, opts_hash: number, env?: table):` returns `chunk: nil|string|fun():string?, modpath: string?, err: string?`:
        - in this form, `chunk` is of the types accepted by the lua `load` function, and `modpath` is the full path to the module.
    - `fun(n: string, search_opts: table, opts_hash: number, env?: table):` returns `chunk: fun():any?, meta: fnFinder.Meta?, err: string?`:
        - in this form, `chunk` is like the lua function you would recieve from calling the `load` function yourself, and you also return a full `fnFinder.Meta` instance.
* `search_opts` (`table?`): Options passed to the `search` function.
* `cache_opts` (`table?`): Options passed to the `get_cached` and `cache_chunk` functions. The default implementations accept:
    - `cache_dir` (`string?`): The directory to cache chunks in, defaults to `"/tmp/fnFinder/"`
    - `mkdir` (`fun(dir: string): string?`): Alternate function to create a directory
* `get_cached` (`fun(modname: string, cache_opts: table): (string | fun(): string?, fnFinder.Meta)?`): Alternate function to retrieve a cached chunk and its metadata.
* `cache_chunk` (`fun(chunk: string, meta: fnFinder.Meta, cache_opts: table)?`): Alternate function to write a chunk and its metadata to cache.
* `fs_lib` (`fun(modname: string): fnFinder.FileAttrs?`): Alternate function to retrieve file system metadata, used for invalidation.
* `auto_invalidate` (`boolean?`): Whether to automatically invalidate cache entries by comparing metadata, defaults to `true`.
* `strip` (`boolean?`): Whether to strip lua debug info from cached chunks, defaults to `false`.
* `env` (`table?`): Table representing the execution environment for loaded modules (passed to lua `load` function if provided)

#### Returns:

* `function(modname: string): string | function | nil`: A function to resolve and load a module by name, suitable for use in `package.loaders` or `package.searchers`.

---

## 🌿 fnFinder.fnl { `mkFinder`, `install` }


### `fnFinder.fnl.mkFinder(loader_opts?: fnFinder.FennelOpts): (modname: string) -> string|function|nil`

Creates a Fennel-aware module loader suitable for use in `package.loaders` or `package.searchers`.

This function wraps `MAIN.mkFinder` with a default `search` function that compiles Fennel source code into Lua bytecode using the `fennel` compiler. It can be customized with various Fennel-specific options.

#### Parameters:

* `loader_opts` (`fnFinder.FennelOpts?`): Optional table of loader customization options.

##### `fnFinder.FennelOpts` (extends `fnFinder.LoaderOpts`):

* `search_opts` (`fnFinder.FennelSearchOpts?`): Options specific to Fennel module resolution.

##### `fnFinder.FennelSearchOpts`:

* `path` (`string | fun(modname: string, existing: string): string`): Custom path string or function to resolve the module file.
* `macro_path` (`string | fun(existing: string): string`): Path or function to adjust Fennel’s `macro-path`.
* `macro_searchers` (`fun(modname: string): string | function?` | array): Additional macro searchers to be added to `fennel["macro-searchers"]`.
* `compiler` (`table?`): Options table to pass to `fennel.compileString`.

#### Returns:

* `function(modname: string): string | function | nil`: A Fennel-compatible module finder.

---

### `fnFinder.fnl.install(pos_or_opts: number | fnFinder.FennelOpts?, opts?: fnFinder.FennelOpts)`

Registers the Fennel module finder into Lua’s module searchers list (`package.loaders` or `package.searchers`).

#### Parameters:

* `pos_or_opts` (`number | fnFinder.FennelOpts?`): If a number, inserts at that position. If a table, uses it as options.
* `opts` (`fnFinder.FennelOpts?`): Used only if the first parameter is a number.

---

## 🔎 Custom search function helpers:

For convenience of users adding different lua dialects and search path configurations

### `fnFinder.searchModule(modulename: string, pathstring: string): string?`

Searches for a Lua module file by replacing `?` in each path template with the module name.

#### Parameters:

* `modulename` (`string`): The name of the module to search for.
* `pathstring` (`string`): A `package.path`-like string with path templates.

#### Returns:

* `string?`: The first valid file path found, or `nil` if none match.

#### Example:

```lua
local modpath = fnFinder.searchModule("mymodule", "lua/?.lua;?/init.lua")
-- checks lua/mymodule.lua and mymodule/init.lua
```

---

### `fnFinder.pkgConfig: { dirsep: string, pathsep: string, pathmark: string }`

A convenience table for path parsing and substitution tokens, from Lua’s `package.config`.

#### Fields:

* `dirsep` (`string`): Directory separator (e.g. `'/'` on Unix, `'\\'` on Windows).
* `pathsep` (`string`): Path separator used to separate search paths (e.g. `';'`).
* `pathmark` (`string`): Placeholder used in path templates to be replaced with the module name (e.g. `'?'`).

#### Example:

```lua
print(require("fnFinder").pkgConfig.dirsep) --> '/'
```

---

### `fnFinder.escapepat(str: string): string`

Escapes all non-alphanumeric characters in a string so that it can safely be used in a Lua pattern.

#### Parameters:

* `str` (`string`): The string to escape.

#### Returns:

* `string`: The escaped pattern-safe string.

#### Example:

```lua
local pat = fnFinder.escapepat("foo?.lua")
-- returns "foo%?%.lua"
```

---
