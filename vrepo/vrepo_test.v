// Unit + fixture tests for vrepo.
module vrepo

import os

fn fixture() string {
	return os.join_path(@VMODROOT, 'testdata', 'fixture')
}

fn test_wildcard_match() {
	assert wildcard_match('junk.log', 'junk.log')
	assert wildcard_match('*.log', 'junk.log')
	assert !wildcard_match('*.log', 'junk.txt')
	assert wildcard_match('*.v', 'code.v')
	assert wildcard_match('build', 'build')
	// exact-only: bare patterns do not touch deeper paths
	assert !wildcard_match('build', 'build/x')
}

fn test_load_gitignore_subset() {
	pats := load_gitignore(fixture())
	assert pats.contains('build/') && pats.contains('junk.log'), pats.str()
}

fn test_matches_ignores() {
	pats := ['build/', 'junk.log', 'gen/*.v']
	assert matches_ignores('junk.log', false, pats)
	assert matches_ignores('build', true, pats)
	assert !matches_ignores('build', false, pats)
	assert matches_ignores('gen/out.v', false, pats)
	assert !matches_ignores('lib/out.v', false, pats)
}

fn test_collect_respects_gitignore() {
	paths := collect(fixture()).map(it.path)
	assert paths.contains('lib/code.v'), paths.str()
	assert paths.contains('cmd/fix/main.v')
	assert paths.contains('.gitignore')
	assert !paths.contains('junk.log')
	assert !paths.contains('build/artifact.txt')
}

fn test_symbols_from_src_on_fixture_file() {
	content := os.read_file(os.join_path(fixture(), 'lib', 'code.v'))!
	syms := symbols_from_src(content)
	names := syms.map(it.name)
	assert syms.len == 5, '${syms.len}'
	assert names.contains('answer'), names.str()
	assert names.contains('Point')
	assert names.contains('add_vals')
	assert names.contains('internal_helper')
	assert names.contains('hypot')
	assert syms[0].kind == 'const', syms[0].kind
	assert syms[0].line == 1, '${syms[0].line}'
}

fn test_vmod_line_from_fixture() {
	line := vmod_line(os.join_path(fixture(), 'v.mod'))
	assert line.contains('module: flib 0.2.0 [MIT]'), line
	assert line.contains('deps: https://github.com/example/bar, github.com/example/baz'), line
}

fn test_brief_full_shape() {
	out := brief(fixture(), Budget{})!
	assert out.contains('vrepo brief — '), out
	assert out.contains('module: flib 0.2.0 [MIT]'), out
	assert out.contains('entry points: cmd/fix/main.v'), out
	assert out.contains('deps: https://github.com/example/bar, github.com/example/baz'), out
	// entry detection only trusts V sources, not non-V files with `fn main`
	assert out.contains('entry points: cmd/fix/main.v'), out
	assert !out.contains('entry points: docs.md'), out
	// tree lists every file, sorted by path
	assert out.contains('  cmd/fix/main.v'), out
	assert out.contains('  lib/code.v'), out
	icmd := out.index('  cmd/fix/main.v') or { -1 }
	ilib := out.index('  lib/code.v') or { -1 }
	assert icmd < ilib, '${icmd} vs ${ilib}'
	// outlined symbols are tab-separated and present
	assert out.contains('\tadd_vals'), out
	// ignored files never surface
	assert !out.contains('junk.log'), out
	assert !out.contains('artifact'), out
}

fn test_brief_error_on_missing_dir() {
	bad := brief('/nonexistent_vrepo_${os.getpid()}', Budget{}) or { return }
	assert false, 'expected an error, got: ${bad}'
}

fn test_budget_default_fits_fixture() {
	out := brief(fixture(), Budget{})!
	assert out.len <= 40_000, '${out.len}'
	assert !out.contains('hidden: brief budget'), out
}

fn test_budget_drops_outline_keeps_tree() {
	// at 350 chars the header+tree fit but the outline block is demoted
	out := brief(fixture(), Budget{ max_chars: 350 })!
	assert out.contains('  lib/code.v'), out
	assert !out.contains('\tadd_vals'), out
}

fn test_budget_hard_truncates() {
	out := brief(fixture(), Budget{ max_chars: 120 })!
	assert out.contains('vrepo brief'), out
	assert out.contains('[truncated'), out
}
