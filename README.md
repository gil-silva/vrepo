# vrepo

Compact, token-efficient repo maps for coding agents.

When a coding AI (Claude Code, OpenCode, Zed, ...) opens a project, its most
expensive activity is not running tools — it's *reading code* to build a mental
model of the repo. `vrepo` answers that with one deterministic artifact: a
small brief holding the module identity, entry points, a file tree with LOC,
and per-file symbol outlines — all capped at a character budget you control.
Point an agent at the brief instead of at the file system and it starts with a
map instead of a maze.

Written in V. Pure V (no subprocesses, no dependencies), same philosophy as
[v-mcp-server](https://github.com/gil-silva/v-mcp-server). MIT.

## Install

Requires [V built from current source](https://github.com/vlang/v) (release
zips lack `vlib/json2`-era stdlib refinements this builds against):

```bash
git clone https://github.com/vlang/v && cd v && make   # put ./v on PATH
v install gil-silva.vrepo        # once indexed on vpm
# — or, immediately after a push, before the registry index catches up:
v install https://github.com/gil-silva/vrepo
```

The import path depends on which install you used:
the indexed install imports as `gil_silva.vrepo.vrepo` (grouped-module
layout, like `crystallib.core`); the direct-URL install as `vrepo.vrepo`.
Both resolve to the same `vrepo` module.

## CLI

```bash
mkdir -p bin && v -no-parallel -o bin/vrepo .   # build the CLI from source
./bin/vrepo /path/to/project > brief.md
```

Example (running it on this repo's own test fixture):

```text
vrepo brief — testdata/fixture
module: flib 0.2.0 [MIT] deps: https://github.com/example/bar, github.com/example/baz
entry points: cmd/fix/main.v
files: 4 (37 loc)
tree:
  .gitignore (4 loc)
  cmd/fix/main.v (6 loc)
  lib/code.v (20 loc)
  v.mod (7 loc)
cmd/fix/main.v
    4	fn	main
lib/code.v
    1	const	answer
    3	struct	Point
    9	fn	add_vals
    13	fn	internal_helper
    17	method	hypot
```

## Library

```v
import gil_silva.vrepo.vrepo

fn main() {
	brief := vrepo.brief('/home/you/project', vrepo.Budget{}) or { panic(err) }
	print(brief)
}
```

`Budget{ max_chars: 40_000 }` is the cap (~10k tokens at ~4 chars/token).
Files that don't fit keep their names in the tree but lose their symbol
outlines; the brief never silently grows past the budget.

## What's in a brief

1. **Module line** — `name`, `version`, `license`, `dependencies` from `v.mod`
2. **Entry points** — every file declaring `fn main`
3. **Tree** — every non-ignored file with LOC count, sorted by path
4. **Outlines** — per-`.v`-file symbol tables (const/fn/method/struct/
   interface/enum/type + line numbers), fn-main files first, then files with
   more symbols; ties break alphabetically so the same tree always yields the
   same brief.

## Determinism & ignore rules

Identical trees produce identical briefs (sorted everywhere, no timestamps).
The root `.gitignore` is honored for a pragmatic subset: comments, blank
lines, trailing `/` (directories only), single `*` wildcards, patterns
containing `/` anchored at root. Standard dirs `.git`, `node_modules` and
`bin` are always skipped. `!` negations and `**` are not interpreted — they
are ignored, so patterns that need them won't protect your files.

## Status

v0.1.0 — first usable version, exercised on this repo and its fixture.
Natural next steps (not built yet): MCP tool wrapper, nested `.gitignore`
support, `**` patterns, import-graph section.

## License

MIT — see [LICENSE](LICENSE).
