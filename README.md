# 💤 LazyVim

A starter template for [LazyVim](https://github.com/LazyVim/LazyVim).
Refer to the [documentation](https://lazyvim.github.io/installation) to get started.

## API search by language (offline, non-AI)

This setup uses **lazy.nvim / LazyVim and Snacks Picker**. The configured AI
plugins are **Supermaven and Opencode**, not Codeium/Windsurf. Python LSP is
not enabled; this feature does not require or change LSP configuration.

Press **`<leader>ph`** (normally Space, p, h) to choose a **language**, then its
search source. Press **`<leader>pH`** (capital H) to use the current buffer's
language and proceed directly to its source chooser. If that filetype has no
profile yet, a message explains this and the language chooser opens instead.

**Profiles are available for Python, TypeScript, C, C++, Rust, and Haskell.**
Python’s sources are **Standard library**
and **Installed packages**. Choosing installed packages opens the package picker,
then searches only the chosen package's APIs. The first build runs in a background
Python process; subsequent searches reuse its cache. Choosing a language or source
does not itself build or download anything. Canceling a chooser performs no search.

`:ApiSearch iterable key` opens the language chooser carrying that query through
the flow. `:ApiSearchCurrent Callable Iterable` uses the buffer's filetype.
The language chooser always appears for `ph`, including when only one profile is
registered. A future profile with one source can open that source directly.

Commands: `:PythonApiSearch itertools.groupby` for the standard library,
`:PythonApiPackages` for the package chooser, or
`:PythonApiPackage requests requests.get` to open a package directly with a query.
`:PythonApiPackages get` carries `get` into the chosen package's API search.
Use `:PythonApiPackage! requests` to rebuild that package after installing or
upgrading it. No packages are imported or executed, and no package dependencies
are installed by this feature.

Search covers qualified names, parameters, and annotation text. Space-separated
terms use Snacks' native matching syntax; results are fuzzy text matches, not
semantic type unification. A package search covers that package's own modules,
not its entire dependency graph.

The preview shows the selected overload, available docstrings, stub location,
and conditional version/platform guards. **Enter** opens a scratch detail
buffer (`q` closes it); **Ctrl-o** in the picker opens the official Python docs
search for standard-library APIs, or a Google documentation search for package APIs. Stub signatures remain available offline. Typeshed usually
has no prose docstrings; full prose documentation requires a browser connection.

### Installation and rebuilding

Requires existing Neovim 0.11+, Snacks, Python 3.9+ (`python3`), and Git.
No pip packages or additional plugins are required. This installation has already
built the cache from [Typeshed](https://github.com/python/typeshed).

- `:PythonApiSetup`: initial network clone and build; reuses an existing checkout.
- `:PythonApiRebuild`: rebuild from local stubs, completely offline.
- `:PythonApiUpdate`: explicitly update the checkout and rebuild (network).

Data lives in `stdpath('cache')/python-api/`: `index.json`, `typeshed/`, and
`revision` (the downloaded Git revision). Builds run asynchronously; failed builds
retain the previous index. Parse failures are reported and recorded in JSON.
Package indexes are stored separately under `python-api/packages/<environment-key>/`.
Changing environments selects a different package cache. Existing package caches
are refreshed explicitly with `:PythonApiPackage! name`; installing packages does
not start a background watcher or trigger an automatic full scan.
No indexed Python modules are imported or executed. Python runs with `-I -S` to
avoid site initialization and project Python hooks. Missing or corrupt indexes
produce instructions to rebuild.

Set options in `lua/config/options.lua`, before plugin initialization:

```lua
vim.g.api_search_key = '<leader>ph'
-- Optional explicit interpreter; overrides automatic interpreter selection:
-- vim.g.python_api_python = '/path/to/python3'
vim.g.api_search_current_key = '<leader>pH'
-- Optional environment override (otherwise activated venv/Conda, project
-- .venv/venv within the project root, then the default interpreter):
-- vim.g.python_api_environment = '/path/to/venv'
-- Optional existing Typeshed stdlib directory:
-- vim.g.python_api_typeshed = '/path/to/typeshed/stdlib'
-- Optional additional site-packages roots:
-- vim.g.python_api_extra_roots = { '/path/to/site-packages' }
```

Package discovery runs the selected interpreter with `-I -S`. It reads environment
paths and virtualenv configuration without loading `site`, executing `.pth` files,
or importing packages. Normal interpreter and user site-packages are included;
isolated virtualenvs exclude them unless `include-system-site-packages` is enabled.
Explicit interpreters take priority over automatic environment detection; an
explicit environment prefix can be supplied alongside the interpreter.

Package indexing parses `.pyi` files first, then `.py` files where stubs are absent.
It supports stub-only distributions (`*-stubs`), standalone Python modules,
namespace package directories, functions/methods, and static re-exports.
Source docstrings are included when available. Missing type annotations remain
missing; there is no runtime introspection. Tests/examples are skipped.
Compiled/dynamically generated APIs without source or stubs, dynamic exports,
and editable installs requiring `.pth` execution are not fully covered.

### Performance

Normal startup/editing does not read package indexes, import packages, run a
package watcher, or build anything. The package chooser only discovers names;
a build is launched on demand for the selected package. Only that package's JSON
is read for search, and previews are constructed for the selected result rather
than eagerly for every API. Picker memory can be reclaimed when it is no longer retained and Lua runs its
garbage collector; process RSS may not fall immediately.

Measured on this machine: requests indexed 1,088 records in about **1.1 s** with
**19 MB** peak indexer memory; NumPy indexed 9,350 records in about **4.2 s** with
**45 MB** peak indexer memory. These are separate-process build costs, not Neovim
startup costs. Large individual packages can still need noticeable indexing time
and picker memory. Indexing all installed packages together is deliberately not
the editor default. Cached picker measurements were about **126 ms / +1.4 MB**
for requests and **318 ms / +22 MB** for NumPy in a headless Neovim check (including
a 50 ms UI wait); these are approximate and depend on the environment.

### Adding language profiles gradually

The dispatcher reuses Snacks. Profiles declare supported filetypes and named
search sources; each source opens its own backend. Metadata loads when a chooser
is opened; backends should be required inside `open`, not at module load time.
Existing `:PythonApi*` commands remain direct shortcuts. The older
`python_api_key` and `python_api_packages_key` option names are fallback aliases
for the general keymaps; the new option names take precedence. Their mapping
behavior now follows the language/source flow rather than jumping straight into
Python.

For example, add a profile module and register it alongside Python:

```lua
-- lua/config/api_search/profiles/example.lua
return {
  id = 'example',
  label = 'Example language',
  filetypes = { 'example' },
  sources = {
    {
      id = 'local',
      label = 'Local APIs',
      open = function(query)
        require('config.example_api').search(query)
      end,
    },
  },
}
```

```lua
-- lua/config/options.lua: explicit list of enabled profile modules
vim.g.api_search_profiles = {
  'config.api_search.profiles.python',
  'config.api_search.profiles.typescript',
  'config.api_search.profiles.c',
  'config.api_search.profiles.cpp',
  'config.api_search.profiles.rust',
  'config.api_search.profiles.haskell',
  'config.api_search.profiles.example', -- register after implementing its backend
}
```

The example is a template, not an included language/backend. Only implemented
profiles should be registered. Profile IDs must be unique; sources also need
unique IDs within their profile. Invalid/failed profiles are reported and skipped.
If multiple profiles support a filetype, `pH` offers those matching profiles.
If none are configured, the dispatcher reports that instead of choosing Python.
Profiles may use different static indexes or documentation tools. Sharing an
entry point does not imply universal indexing or semantic type unification.

### AI-free interview practice

Use **`<leader>uI`**, or `:InterviewPractice on`, `off`, `toggle`, or `status`.
Start directly in practice mode with `NVIM_INTERVIEW=1 nvim`.
The statusline shows **AI OFF** during practice and **AI allowed** otherwise.
“AI allowed” means the integrations are permitted; it does not assert that a
backend is running. The indicator uses the existing statusline and adds no plugin.

Practice mode stops Supermaven, clears suggestions, blocks its startup/completion
source, stops editor-managed Opencode, and guards its configured actions and
public entrypoints. Ordinary completion, diagnostics, navigation, and hover remain
available. Turning practice off restores a previously running Supermaven backend
and allows Opencode actions again without automatically opening chat. The toggle
is session-local. It does not control external AI applications or independently
started Opencode servers. Codeium/Windsurf are not installed by this change; if
adding another AI provider later, extend practice mode before relying on it.

### Verified searches and limitations

The initial standard-library checkout indexed 24,865 records with zero parse errors. All of these
queries produced matches through the actual Snacks matcher:

| Query | Useful examples / interpretation |
| --- | --- |
| `sorted` | `builtins.sorted`; many unrelated fuzzy matches also appear |
| `itertools.groupby` | Class constructor overloads and iterator methods |
| `collections` | Module, classes, and methods |
| `iterable key` | `heapq.nsmallest`, sorting and grouping signatures |
| `list[str]` | String-list annotations, including parameter annotations |
| `Callable` | Callback parameters and related annotations |
| `Callable Iterable` | Signatures containing both textual concepts |
| `Iterator[T]` | Generic iterator annotations, including `Iterator[_T]` |
| `asyncio gather` | `asyncio.gather` and `asyncio.tasks.gather` overloads |

Search does not distinguish return annotations from parameter annotations, expand
aliases such as `_FutureLike`, infer missing annotations, or unify generic types.
Fuzzy matches can be noisy; use a qualified name or Snacks' exact-match prefix
(single quote) to narrow results. Constructors retain the stub's `cls`/`self`
parameter. Overloads are grouped into one result with their signatures retained in the preview. Version/platform branches are all
indexed with guards, not evaluated; APIs may differ from your active Python.
Static re-export resolution is bounded and cannot reproduce arbitrary dynamic
exports. Documentation search links avoid assuming every private stub symbol has
a dedicated documentation anchor.

### Tests

```sh
python3 -I -S -m unittest discover -s tests -v
NVIM_INTERVIEW=1 nvim --headless -i NONE \
  '+luafile tests/python_api_headless.lua' '+qa!'
```

Installed-package integration can also be tested with an environment containing
requests:

```sh
NVIM_INTERVIEW=1 nvim --headless -i NONE \
  '+luafile tests/python_packages_headless.lua' '+qa!'
```

The original headless integration test requires a built standard-library index. It checks AI startup guards,
completion availability, mode restoration with a simulated backend, public API
entries, representative native matcher queries, picker creation, and the keymap.
Existing Mason repository-rename warnings are unrelated to this feature.

### Autosave

Autosave retains its 1.5-second delay and only writes existing, writable regular
files. Unnamed, read-only, terminal, documentation, and other special buffers are
excluded. Use `:w` to create a new named file before relying on autosave.

## General project workflows

These tools reuse Snacks pickers/scratch buffers and Persistence. No language
servers, debuggers, runtime packages, or additional plugins are installed.
Project metadata is read only when invoked; startup does not scan `~/Programming`.

| Key | Command | Action |
| --- | --- | --- |
| `<leader>pp` | `:ProjectPick` | Choose a project under `~/Programming` |
| `<leader>pw` | `:ProjectWorktrees` | Choose an existing Git worktree |
| `<leader>pe` | `:ProjectContext` | Select Python, JS manager, or CMake build directory |
| `<leader>pt` | `:ProjectTasks` | Choose any discovered task |
| `<leader>pr` | `:ProjectRun` | Run a standalone file or choose a project run target |
| `<leader>pb` | `:ProjectBuild` | Choose a build task |
| `<leader>pT` | `:ProjectTest` | Choose tests for the current package/project |
| `<leader>pl` | `:ProjectRepeat` | Rerun the last task for this project |
| `<leader>po` | `:ProjectOutput` | Reopen a retained task log and its quickfix diagnostics |
| `<leader>px` | `:ProjectStop` | Stop a running task or sample-case suite |
| `<leader>pc` | `:ProjectCases` | Run input/output cases for the current source |
| `<leader>pC` | `:ProjectCaseEdit` | Create/edit a named sample input and expected output |
| `<leader>ps` | `:ProjectScratch` | Choose a language and open its project scratchpad |
| `<leader>pS` | `:ProjectSymbols` | LSP document symbols, falling back to Treesitter |

Project selection preserves buffers and opens a file picker in the new directory.
Ctrl-s in the project picker explicitly saves/restores sessions. Save modified
buffers before using that alternate action. Tasks and developer servers are not
automatically started by project selection or session restoration. Existing
worktrees remain separate contexts; none are created or deleted by the picker.
The `.git` in `~/Programming` does not become the root of every child project.

### Task discovery and execution

Tasks show their working directories. In monorepos, scripts from the current
package and its ancestors are separate entries. JavaScript commands respect
`packageManager` declarations, then lockfiles, then npm; a selected project
manager overrides detection. Every script is selectable, including maintenance
scripts: execution happens only when you explicitly select it.

Adapters cover Cargo build/test/check and statically discoverable binary targets;
configured CMake/CTest builds; Gradle build/test; PlatformIO build/test; Go;
Nimble; Cabal/Stack; Dune; Spago; Python pytest; and straightforward Make/Just
targets. Cargo metadata recognition is deliberately limited to ordinary quoted
package/binary names and literal workspace member globs. Complex/dynamic project
configurations can supply custom tasks. CMake must already be configured; select
an existing build directory through `:ProjectContext`. Its run task asks you to
choose an actual executable rather than guessing artifact paths.

Run/build/test commands use argument arrays in asynchronous jobs. Output streams
into a retained bottom split, reused per project, with separate logs for each
task. This is a log viewer rather than an interactive terminal; use your existing
terminal mappings for REPLs, password prompts, and other interactive commands.
Logs remain in memory for the current Neovim session. Standard compiler
`file:line[:column]` locations, Python tracebacks, and Rust compiler locations go
to quickfix. Custom tasks can provide `errorformat`; unrecognized output remains
available in the log. Existing quickfix navigation and Trouble still work.

Standalone runners cover Python, JS/TS (TypeScript requires Bun), Lua, shell, Go,
Haskell, OCaml, Mojo, C/C++, Rust, and Nim when their tools are installed. Compiled
snippets write binaries/build caches into Neovim's cache. Files belonging to a
compiled project use project run targets instead. Framework components and
snippets requiring project build configuration should use their project tasks.
Missing tools are reported and never installed automatically.

The test shortcut chooses an existing package/project test task; it does not
promise nearest-test discovery across all languages. Additional test runners,
executable arguments, complex targets, and unusual project layouts can use the
custom task configuration below.

### Scratchpads and sample cases

Choose a scratch language with `<leader>ps`, then use **`<localleader>r`** inside
that buffer to run it. Scratch files are retained per project under Neovim's state
directory. Snippets are standalone; dependencies requiring a project's original
source location or build flags should use a project task. Lua scratch execution
uses an installed `lua` executable; Snacks' existing Lua scratch action is also
available.

For input/output exercises, open the source and press `<leader>pC` to edit a named
`.in`/`.out` pair. Return to the source and press `<leader>pc`. Cases live under
`stdpath('state')/workflow-cases/`, keyed by source path; no files are added to your
repositories. Compiled solutions compile once per suite. Each case has a default
five-second timeout and a 1 MiB stdout limit. Comparison preserves whitespace and
normalizes only CRLF. Failures show a unified expected/actual diff and stderr.
For non-standalone programs, select a project run target with suitable stdin/stdout
behavior. Selected commands must terminate to produce a case result.

Project selections/history live in `stdpath('state')/workflow.json`. Only task
identifiers and explicit context selections are persisted; inherited environments
and custom task environment values are not saved there. Full ad-hoc file command
snapshots are session-local; after restarting, repeat can resolve discovered tasks
by their saved identifier. The statusline shows active task count and explicit
Python/JavaScript context when applicable.

### Configuration

Set this data table in `lua/config/options.lua` before startup:

```lua
vim.g.project_workflow = {
  roots = { vim.env.HOME .. '/Programming' },
  keys = { Tasks = '<leader>pt' }, -- other keys use the command suffix, e.g. Run
  case_timeout_ms = 5000,
  case_output_limit_bytes = 1048576,
  tasks = {
    {
      name = 'Run my application',
      root = '/absolute/project/root', -- omit to offer in every project
      cwd = '/absolute/project/root',
      argv = { './build/application', '--verbose' },
      kind = 'run', -- run, build, test, or task
      -- env = { APP_MODE = 'development' },
      -- errorformat = '%f:%l:%c: %m',
    },
  },
}
```

`:ProjectContext` selections are per project/worktree. Enter `auto` in the Python
or CMake path prompt to clear that override. The Python interpreter is
shared with package API search. Existing global `python_api_*` options continue
to apply when there is no project-specific interpreter selection.

Python API results now group overloads, favor exact names, and hide private
symbols by default. **Alt-p** toggles private results; **Ctrl-s** opens the selected
symbol's source. All overload annotation text remains searchable, and previews
are generated only for the selected result.

### Workflow verification

```sh
NVIM_INTERVIEW=1 nvim --headless -i NONE \
  '+lua local ok,e=pcall(dofile,"tests/workflow_headless.lua"); if not ok then print(e); vim.cmd("cquit 1") end' '+qa!'
NVIM_INTERVIEW=1 nvim --headless -i NONE \
  '+lua local ok,e=pcall(dofile,"tests/api_picker_headless.lua"); if not ok then print(e); vim.cmd("cquit 1") end' '+qa!'
```

Workflow tests execute only temporary fixtures, including paths containing spaces,
case comparisons/timeouts/output limits, scratch execution, cancellation, and
failure statuses. Discovery/worktree listing in qafiyah, Watad, sarj-drill,
svelte-purs, RoverSim, and AnkiDroid-Companion is read-only; their tasks are not run.

Validation on this machine found 81 task choices at qafiyah's root, six in Watad,
and tasks in each of the other representative projects. These counts depend on
current manifests and configured build directories. The fixture suite also
compiles a small C program when `cc` is available and checks that a two-case suite
compiles it only once. Startup checks confirm that workflow modules remain
unloaded after startup/VeryLazy; there is no project-tree scan in that path.
A measured headless startup including forced VeryLazy was about 0.7 seconds, and
cached grouped requests search was about 0.22 seconds. These are whole-operation
measurements, not an isolated before/after overhead comparison.


Profile routing, cancellation, lazy loading, compatibility and native picker tests:

```sh
NVIM_INTERVIEW=1 nvim --headless -i NONE \
  '+lua local ok,e=pcall(dofile,"tests/api_profiles_headless.lua"); if not ok then print(e); vim.cmd("cquit 1") end' '+qa!'
```


## TypeScript, C, C++, Rust, and Haskell API sources

All six languages appear in `<leader>ph`. `<leader>pH` recognizes TypeScript/TSX,
C, C++, Rust, Haskell/literate Haskell, and Python buffers. An explicit
`api_search_profiles` list replaces the defaults; include the profiles you want.

| Profile | Search collections |
| --- | --- |
| TypeScript | Standard declaration libraries; installed packages; project source |
| C | Whole standard library; optional specific header; project source |
| C++ | Whole installed standard library; optional specific header; project source |
| Rust | Whole local std documentation; optional specific module; downloaded Cargo crates; project source |
| Haskell | Hoogle online with a query cache; local Hoogle executable/database |

Local declaration indexing requires **Universal Ctags with JSON support** and
Python 3.9+. Both were already installed on this machine. Ctags is invoked with
`--options=NONE`, so project/user Ctags option files are not executed. Indexing
reads declarations rather than importing packages, loading TypeScript compiler
plugins, preprocessing headers, expanding Rust macros, running build scripts, or
building dependency crates. No new plugins or system packages were installed.

Collections build asynchronously only after selection and are stored under
`stdpath('cache')/api-search/`. Subsequent searches reuse the cache. **Ctrl-r** in
the result picker refreshes that collection; `:ApiIndexRebuild` rebuilds the last
local collection selected for the current project/session. Python keeps its
existing setup/rebuild commands. Updating dependencies does not start a watcher;
rebuild explicitly when declarations change.

**Enter** opens grouped signatures/source excerpts, **Ctrl-s** jumps to indexed
source where available, and **Ctrl-o** opens documentation. Rustdoc links point
to the installed offline HTML pages. Other local declaration results use a web
documentation search; their signatures/source excerpts remain available offline.

### Source selection

TypeScript looks for `node_modules/typescript/lib` in the current package and
ancestor directories, then a global `tsc` installation. If unavailable, it asks
for a TypeScript SDK library directory. Choose e.g. `lib.es5.d.ts` for APIs such
as `Array.map`; referenced SDK declaration libraries are followed statically.
Installed packages come from visible `node_modules` directories (including scoped
packages and symlinks). Select one package at a time. The index includes `.ts`,
`.tsx`, `.mts`, and `.cts` sources/declarations. Project indexing skips build
outputs; installed-package indexing includes published declarations in `dist`,
`build`, and `out`. Nested dependencies, examples, and tests are skipped. JavaScript-only packages without declarations
are not covered.

Choose **Standard library** for C, C++, or Rust and start searching directly.
You do not need to identify the function's header or module. The explicit
**Specific header/module (optional)** sources remain available for narrowing a
search, and third-party package selection retains its previous behavior.

C defaults to `/usr/include`. Its standard-library collection starts from the
available ISO C standard headers, follows their literal available includes, and
also looks in the installed compiler's built-in include directory. It does not
indiscriminately scan every third-party/POSIX header under `/usr/include`; other
headers can use the optional header source or a configured SDK include directory.

C++ selects an installed GCC standard-header directory under `/usr/include/c++/`
and indexes its public top-level headers together, following available includes
with cycle protection. There is no header chooser in the default standard-library
flow. Other toolchains and SDKs can override these paths. Preprocessor branches
are not evaluated, so the index reflects available SDK declarations rather than
an exact compilation configuration.

Rust detects the active sysroot with `rustc --print sysroot` and indexes **all**
existing `std` documentation pages under `share/doc/rust/html/std`. Searching
`push`, `collect`, or `HashMap get` therefore spans modules. Qualified queries such
as `std::vec::Vec::push` work too; `::` queries use contiguous text matching to
avoid interpreting namespaces as Snacks field selectors. Space-separated words
retain broad fuzzy matching. This does not install components or run Cargo. If
docs are missing, install `rust-docs` separately or supply a documentation path.
The Cargo package chooser lists already downloaded registry source directories;
it does not fetch missing dependencies. Crate versions appear as separate entries.

Whole-library indexes are built in a separate process only on first selection or
explicit rebuild. C/C++ source excerpts are read only when a result is previewed,
instead of duplicated in the larger cache. Rust signature extraction skips
unrelated HTML prose/examples. Nothing scans or loads these collections during
normal startup. The larger result sets still use more memory while retained by
the picker; process RSS does not necessarily drop immediately after closing it.

Measured on this machine: C indexed 2,139 declarations in about 2 seconds (428 KB
JSON); C++ indexed 34,435 in about 10 seconds (7.5 MB); Rust indexed 51,062 in
about 42 seconds (17 MB). Cached full-collection open/search checks took roughly
0.5 s for `printf`, 1.4 s for `std::sort`, and 2.2 s for
`std::vec::Vec::push`. C++/Rust checks used about 73/117 MB total Neovim RSS,
respectively. These are whole-operation measurements, not startup overhead.
Initial builds stay asynchronous; subsequent lookups reuse the cache. Use Ctrl-r
or `:ApiIndexRebuild` to refresh a local collection after an SDK update.

### Haskell through Hoogle

The **online** source asks for a name or type signature, for example `map` or
`(a -> b) -> [a] -> [b]`, and queries the public `hoogle.haskell.org` JSON endpoint.
Only this explicitly selected source sends the query to that service. It uses
existing `curl`, retains up to 100 results, and caches each exact query. Repeating
a cached query works offline; a new query requires a connection. Ctrl-r refreshes
the cached query. Hoogle's result ordering is preserved before optional local
fuzzy filtering. Ctrl-o opens the associated Hackage documentation page.

The **local** source uses an installed `hoogle` executable and generated database
for offline searches of that database's packages. Hoogle is **not installed on
this machine**, so the online source is ready to use while the local source
reports setup instructions. After installing Hoogle, generate its database using
`hoogle generate`; a custom database path must be used consistently for generation
and search. Installation/database generation is never started by the editor.

### Optional backend settings

```lua
vim.g.api_search_config = {
  typescript = { stdlib = '/absolute/path/to/typescript/lib' },
  c = { headers = '/usr/include', include_roots = { '/usr/include' } },
  cpp = {
    headers = '/absolute/path/to/c++/include',
    include_roots = { '/absolute/path/to/c++/include', '/usr/include' },
  },
  rust = { docs = '/absolute/path/to/share/doc/rust/html/std' },
  haskell = { executable = 'hoogle', database = '/absolute/path/to/default.hoo' },
}
-- Defaults are python3 and ctags:
-- vim.g.api_index_python = '/path/to/python3'
-- vim.g.api_index_ctags = '/path/to/ctags'
```

### Capabilities and validation

Local Ctags/rustdoc sources provide **textual fuzzy matching**, not semantic type
unification. Hoogle supplies Haskell's own name/type-signature search. Static
source extraction can miss aliases, re-exports, complex multiline declarations,
macro-generated APIs, and conditional compilation effects. Scope names are the
ones available to the parser; Rust source paths are not compiler-resolved export
paths. Private SDK internals may appear. Missing types are not inferred. Parameter
and return annotations share the same searchable text. Previews include source
excerpts rather than guaranteeing full prose documentation for every declaration.

Verified against local SDKs: `printf` in C, `std::vector::push_back` in C++,
`Array.map` in TypeScript, and `std::vec::Vec::push` in installed rustdoc. The public
Hoogle endpoint returned `map :: (a -> b) -> [a] -> [b]`. Fixtures also cover
C/C++/TS/Rust static parsing, cyclic header includes, TypeScript library references,
rustdoc HTML, Hoogle response formatting/operators, and offline query-cache reuse.

```sh
python3 -B -I -S -m unittest discover -s tests -v
NVIM_INTERVIEW=1 nvim --headless -i NONE \
  '+lua local ok,e=pcall(dofile,"tests/multilang_api_headless.lua"); if not ok then print(e); vim.cmd("cquit 1") end' '+qa!'
```
