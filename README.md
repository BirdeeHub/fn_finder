# fn_finder

I wanted to try fennel

I did not want to add a build step to my configurations

I did not want to be unsatisfied with the extra overhead of a transpiler at runtime, especially one with compile time evaluation.

I might want to try some other lua dialects in the future.

`mkFinder` and its helpers makes changing languages just 1 short function passed in via option.

You can also change how it caches. Maybe you want to cache your bytecode to a database instead.

Currently the default search function works for `package.path` and the only other language with a premade search function is fennel.

One will be added that searches the nvim runtime path in the future, but you can do it yourself in the meantime with `vim.loader.find`!

## ⚡Quick Start

- TODO: basic useage here:

---

## 📦 Module: `fn_finder`

### `fn_finder.mkFinder(loader_opts?: fn_finder.LoaderOpts): (modname: string) -> string|function|nil`

The function that provides the core functionality of the `fn_finder` module.

Creates a module loader function suitable for use in `package.loaders` or `package.searchers`, supporting caching and file search customization.

#### Parameters:

* `loader_opts` (`fn_finder.LoaderOpts?`): Optional table of loader customization options.

##### `fn_finder.LoaderOpts`:

* `search`: Accepts one of the following forms:
    - `string`: the string to search as the `package.path` for your lua dialect
    - `fun(n: string, search_opts: table, opts_hash: number, env?: table):` returns `chunk: nil|string|fun():string?, modpath: string?, err: string?`:
        - in this form, `chunk` is of the types accepted by the lua `load` function, and `modpath` is the full path to the module.
    - `fun(n: string, search_opts: table, opts_hash: number, env?: table):` returns `chunk: fun():any?, meta: fn_finder.Meta?, err: string?`:
        - in this form, `chunk` is like the lua function you would recieve from calling the `load` function yourself, and you also return a full `fn_finder.Meta` instance.
* `search_opts` (`table?`): Options passed to the `search` function.
* `cache_opts` (`table?`): Options passed to the `get_cached` and `cache_chunk` functions. The default implementations accept:
    - `cache_dir` (`string?`): The directory to cache chunks in, defaults to `"/tmp/fn_finder/"`
    - `mkdir` (`fun(dir: string): string?`): Alternate function to create a directory
* `get_cached` (`fun(modname: string, cache_opts: table): (string | fun(): string?, fn_finder.Meta)?`): Alternate function to retrieve a cached chunk and its metadata.
* `cache_chunk` (`fun(chunk: string, meta: fn_finder.Meta, cache_opts: table)?`): Alternate function to write a chunk and its metadata to cache.
* `fs_lib` (`fun(modname: string): fn_finder.FileAttrs?`): Alternate function to retrieve file system metadata, used for invalidation.
* `auto_invalidate` (`boolean?`): Whether to automatically invalidate cache entries by comparing metadata, defaults to `true`.
* `strip` (`boolean?`): Whether to strip lua debug info from cached chunks, defaults to `false`.
* `env` (`table?`): Table representing the execution environment for loaded modules (passed to lua `load` function if provided)

#### Returns:

* `function(modname: string): string | function | nil`: A function to resolve and load a module by name, suitable for use in `package.loaders` or `package.searchers`.

---

## 🌿 fn_finder.fnl { `mkFinder`, `install` }


### `fn_finder.fnl.mkFinder(loader_opts?: fn_finder.FennelOpts): (modname: string) -> string|function|nil`

Creates a Fennel-aware module loader suitable for use in `package.loaders` or `package.searchers`.

This function wraps `MAIN.mkFinder` with a default `search` function that compiles Fennel source code into Lua bytecode using the `fennel` compiler. It can be customized with various Fennel-specific options.

#### Parameters:

* `loader_opts` (`fn_finder.FennelOpts?`): Optional table of loader customization options.

##### `fn_finder.FennelOpts` (extends `fn_finder.LoaderOpts`):

* `search_opts` (`fn_finder.FennelSearchOpts?`): Options specific to Fennel module resolution.

##### `fn_finder.FennelSearchOpts`:

* `path` (`string | fun(modname: string, existing: string): string`): Custom path string or function to resolve the module file.
* `macro_path` (`string | fun(existing: string): string`): Path or function to adjust Fennel’s `macro-path`.
* `macro_searchers` (`fun(modname: string): string | function?` | array): Additional macro searchers to be added to `fennel["macro-searchers"]`.
* `compiler` (`table?`): Options table to pass to `fennel.compileString`.

#### Returns:

* `function(modname: string): string | function | nil`: A Fennel-compatible module finder.

---

### `fn_finder.fnl.install(pos_or_opts: number | fn_finder.FennelOpts?, opts?: fn_finder.FennelOpts)`

Registers the Fennel module finder into Lua’s module searchers list (`package.loaders` or `package.searchers`).

#### Parameters:

* `pos_or_opts` (`number | fn_finder.FennelOpts?`): If a number, inserts at that position. If a table, uses it as options.
* `opts` (`fn_finder.FennelOpts?`): Used only if the first parameter is a number.

---

## 🔎 Custom search function helpers:

For convenience of users adding different lua dialects and search path configurations

### `fn_finder.searchModule(modulename: string, pathstring: string): string?`

Searches for a Lua module file by replacing `?` in each path template with the module name.

#### Parameters:

* `modulename` (`string`): The name of the module to search for.
* `pathstring` (`string`): A `package.path`-like string with path templates.

#### Returns:

* `string?`: The first valid file path found, or `nil` if none match.

#### Example:

```lua
local modpath = fn_finder.searchModule("mymodule", "lua/?.lua;?/init.lua")
-- checks lua/mymodule.lua and mymodule/init.lua
```

---

### `fn_finder.pkgConfig: { dirsep: string, pathsep: string, pathmark: string }`

A convenience table for path parsing and substitution tokens, from Lua’s `package.config`.

#### Fields:

* `dirsep` (`string`): Directory separator (e.g. `'/'` on Unix, `'\\'` on Windows).
* `pathsep` (`string`): Path separator used to separate search paths (e.g. `';'`).
* `pathmark` (`string`): Placeholder used in path templates to be replaced with the module name (e.g. `'?'`).

#### Example:

```lua
print(require("fn_finder").pkgConfig.dirsep) --> '/'
```

---

### `fn_finder.escapepat(str: string): string`

Escapes all non-alphanumeric characters in a string so that it can safely be used in a Lua pattern.

#### Parameters:

* `str` (`string`): The string to escape.

#### Returns:

* `string`: The escaped pattern-safe string.

#### Example:

```lua
local pat = fn_finder.escapepat("foo?.lua")
-- returns "foo%?%.lua"
```

---
