// vrepo
// Compact, token-efficient repo maps for coding agents.
//
// One call — `brief(root, Budget{})` — returns a plain-text brief of a V
// project: the v.mod summary, entry points, a file tree with LOC, and
// per-file symbol outlines, ordered by usefulness and capped at a
// character budget (files that overrun keep their names in the tree but
// lose their outlines).
//
// Deterministic by construction: directory listings are sorted, the same
// tree always yields the same brief. Only the root .gitignore is honored
// (subset: comments, blank lines, trailing `/` for dirs, single `*`
// wildcards, anchored patterns containing `/`; `!` and `**` are ignored).
module vrepo

import os

// Budget caps the character size of a generated brief
// (~4 characters per token, so 40_000 ≈ 10k tokens).
pub struct Budget {
pub:
	max_chars int = 40_000
}

// VFile is one collected file with its outline and stats.
struct VFile {
	path   string // relative to root, '/'-separated
	loc    int
	syms   []Symbol
	has_fn bool // declares `fn main(...)`
}

// Symbol mirrors the declaration kinds of a `.v` file.
struct Symbol {
	kind string
	name string
	line int
}

// dirs never descended into (besides .gitignore matches).
const skip_dirs = ['.git', 'node_modules', 'bin']!

// brief generates the repo brief for the V project (or plain directory)
// at root, capped at b.max_chars. Errors if root is not a directory.
pub fn brief(root string, b Budget) !string {
	if !os.is_dir(root) {
		return error('not a directory: ${root}')
	}
	vfiles := collect(root)
	hdr := header(root, vfiles)
	tree := tree_lines(vfiles)

	// Outlines, most interesting first: fn-main files (path asc), then
	// remaining .v files by symbol count desc with path as tie-break.
	mut outlined := vfiles.filter(it.syms.len > 0)
	// desc file_rank, asc path on ties — sort() only allows direct a/b compares.
	outlined.sort_with_compare(fn (x &VFile, y &VFile) int {
		rx := file_rank(x)
		ry := file_rank(y)
		if rx != ry {
			return if rx > ry { -1 } else { 1 }
		}
		return if x.path < y.path {
			-1
		} else if x.path > y.path {
			1
		} else {
			0
		}
	})
	mut body := hdr.join('\n') + '\ntree:\n' + tree.join('\n')
	mut hidden := 0
	mut shown := 0
	for f in outlined {
		block := outline_block(f)
		candidate := body + '\n' + block
		if candidate.len <= b.max_chars {
			body = candidate
			shown++
		} else {
			hidden++
		}
	}
	if shown == 0 && hidden == 0 {
		body += '\n  (none)'
	}
	if hidden > 0 {
		body += '\n[${hidden} file outline(s) hidden: brief budget]'
	}
	if body.len > b.max_chars {
		// header + tree alone overrun; keep the front, mark the cut.
		return body[..b.max_chars] + '\n... [truncated; ${body.len} chars total]'
	}
	return body
}

// file_rank orders outline candidates: has_fn first (as entry points),
// then more symbols; ties break on path (asc) for determinism.
fn file_rank(f VFile) int {
	if f.has_fn {
		return 100_000_000 + f.syms.len
	}
	return f.syms.len
}

// header builds the front lines: identity, entry points, totals.
fn header(root string, vfiles []VFile) []string {
	mut h := ['vrepo brief — ${root}']
	vmod := os.join_path(root, 'v.mod')
	if os.exists(vmod) {
		h << vmod_line(vmod)
	} else {
		h << 'no v.mod (plain directory tree below)'
	}
	entries := vfiles.filter(it.has_fn).map(it.path)
	h << 'entry points: ${if entries.len > 0 { entries.join(', ') } else { 'none' }}'
	mut loc := 0
	for f in vfiles {
		loc += f.loc
	}
	h << 'files: ${vfiles.len} (${loc} loc)'
	return h
}

// vmod_line folds the interesting v.mod fields into one line.
fn vmod_line(vmod string) string {
	content := os.read_file(vmod) or { return 'v.mod unreadable' }
	mut name := ''
	mut version := ''
	mut license := ''
	mut deps := []string{}
	for raw in content.split_into_lines() {
		line := raw.trim_space()
		if line.starts_with('name:') {
			name = field_value(line)
		} else if line.starts_with('version:') {
			version = field_value(line)
		} else if line.starts_with('license:') {
			license = field_value(line)
		} else if line.starts_with('dependencies:') {
			// NOTE: .after(':') cuts at the LAST colon; use all_after_first
			rest := line.all_after_first(':').trim_space() // e.g. ['a', 'b'] or []
			deps = rest
				.replace('[', '')
				.replace(']', '')
				.replace("'", '')
				.replace('"', '')
				.split(',')
				.map(it.trim_space())
				.filter(it != '')
		}
	}
	dep_note := if deps.len > 0 { deps.join(', ') } else { 'none' }
	lic := if license.len > 0 { ' [${license}]' } else { '' }
	return 'module: ${name}${if version.len > 0 { ' ${version}' } else { '' }}${lic} deps: ${dep_note}'
}

// field_value pulls the value off a `key: value` v.mod line (unquoted).
fn field_value(line string) string {
	return unquote(line.after(':').trim_space())
}

// unquote strips one pair of surrounding quotes (' or ") when present.
fn unquote(s string) string {
	if s.len < 2 || s[0] != s[s.len - 1] || (s[0] != `'` && s[0] != `"`) {
		return s
	}
	return s[1..s.len - 1]
}

// tree_lines renders every collected file, sorted by path.
fn tree_lines(vfiles []VFile) []string {
	mut sorted := vfiles.clone()
	sorted.sort(b.path > a.path)
	mut lines := []string{}
	for f in sorted {
		lines << '  ${f.path} (${f.loc} loc)'
	}
	return lines
}

// outline_block is the symbol table of one file.
fn outline_block(f VFile) string {
	mut b := ['  ${f.path}']
	for s in f.syms {
		b << '    ${s.line}\t${s.kind}\t${s.name}'
	}
	return b.join('\n')
}

// ---- collection ------------------------------------------------------------

// collect walks root depth-first with sorted listings, honoring
// .gitignore subset + skip_dirs, reading each file exactly once.
fn collect(root string) []VFile {
	mut out := []VFile{}
	pats := load_gitignore(root)
	collect_dir(root, '', pats, mut out)
	return out
}

fn collect_dir(root string, rel string, pats []string, mut out []VFile) {
	dir := os.join_path(root, rel)
	mut entries := os.ls(dir) or { return }
	entries.sort(b > a)
	for name in entries {
		rpath := if rel == '' { name } else { '${rel}/${name}' }
		is_dir := os.is_dir(os.join_path(root, rpath))
		if is_dir {
			if name in skip_dirs {
				continue
			}
			if matches_ignores(rpath, true, pats) {
				continue
			}
			collect_dir(root, rpath, pats, mut out)
		} else {
			if matches_ignores(rpath, false, pats) {
				continue
			}
			if content := os.read_file(os.join_path(root, rpath)) {
				lines := content.split_into_lines()
				mut has_fn := false
				for line in lines {
					t := line.trim_space()
					if t.starts_with('fn main(') || t.starts_with('pub fn main(') {
						has_fn = true
						break
					}
				}
				syms := if rpath.ends_with('.v') { symbols_from_src(content) } else { []Symbol{} }
				out << VFile{
					path:   rpath
					loc:    lines.len
					syms:   syms
					has_fn: has_fn
				}
			}
		}
	}
}

// load_gitignore reads the root .gitignore (any missing file → no patterns).
fn load_gitignore(root string) []string {
	mut pats := []string{}
	content := os.read_file(os.join_path(root, '.gitignore')) or { return pats }
	for raw in content.split_into_lines() {
		line := raw.trim_space().trim_left('/')
		if line == '' || line.starts_with('#') || line.starts_with('!') {
			continue
		}
		pats << line
	}
	return pats
}

// matches_ignores applies the supported .gitignore subset to rel ('/'-separated).
fn matches_ignores(rel string, is_dir bool, pats []string) bool {
	for raw in pats {
		mut p := raw
		dir_only := p.ends_with('/')
		if dir_only {
			p = p.trim_right('/')
		}
		if dir_only && !is_dir {
			continue
		}
		if p.contains('/') {
			if wildcard_match(p, rel) {
				return true
			}
		} else {
			// bare pattern → match any path segment (basename at any depth)
			for seg in rel.split('/') {
				if wildcard_match(p, seg) {
					return true
				}
			}
		}
	}
	return false
}

// wildcard_match is the classic two-pointer glob over single '*' runs.
fn wildcard_match(pat string, s string) bool {
	mut pi := 0
	mut si := 0
	mut star := -1
	mut match_len := 0
	for si < s.len {
		if pi < pat.len && (pat[pi] == s[si] || pat[pi] == `?`) {
			pi++
			si++
		} else if pi < pat.len && pat[pi] == `*` {
			star = pi
			match_len = si
			pi++
		} else if star != -1 {
			pi = star + 1
			match_len++
			si = match_len
		} else {
			return false
		}
	}
	for pi < pat.len && pat[pi] == `*` {
		pi++
	}
	return pi == pat.len
}

// ---- symbol outlines (zero-dependency line scanner) ------------------------

// symbols_from_src extracts a rough public-symbol outline: fns, structs,
// interfaces, enums, consts, types and methods. For full navigation use
// v-analyzer or `v ast`; this stays cheap enough to run over a whole tree.
fn symbols_from_src(content string) []Symbol {
	mut syms := []Symbol{}
	for i, raw_line in content.split_into_lines() {
		line := raw_line.trim_space()
		kind := if line.starts_with('pub fn (') {
			'method'
		} else if line.starts_with('pub fn ') || line.starts_with('fn ') {
			'fn'
		} else if line.starts_with('pub struct ') || line.starts_with('struct ') {
			'struct'
		} else if line.starts_with('pub interface ') || line.starts_with('interface ') {
			'interface'
		} else if line.starts_with('pub enum ') || line.starts_with('enum ') {
			'enum'
		} else if line.starts_with('pub const ') || line.starts_with('const ') {
			'const'
		} else if line.starts_with('pub type ') || line.starts_with('type ') {
			'type'
		} else {
			''
		}
		if kind == '' {
			continue
		}
		name := symbol_name_of(kind, raw_line)
		if name.len > 0 {
			syms << Symbol{ kind: kind, name: name, line: i + 1 }
		}
	}
	return syms
}

// symbol_name_of pulls the identifier right after the declaration keyword
// (or the first identifier inside the params, for receiver methods).
fn symbol_name_of(kind string, raw_line string) string {
	toks := raw_line.trim_space().split(' ').filter(it.len > 0)
	if kind == 'method' {
		return method_name(toks)
	}
	for j, token in toks {
		if token == kind && j + 1 < toks.len {
			return toks[j + 1].split('(')[0].split(':')[0]
		}
	}
	return ''
}

// method_name decodes `pub fn (mut s Server) add_tool(...)` → `add_tool`:
// the name is the first token after the one that closes the receiver `)`.
fn method_name(toks []string) string {
	for i, token in toks {
		if token.contains(')') && i + 1 < toks.len {
			name := toks[i + 1].split('(')[0].split(':')[0].trim_space()
			if name.len > 0 {
				return name
			}
		}
	}
	return ''
}
