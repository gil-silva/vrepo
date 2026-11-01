// vrepo CLI — print a compact repo brief for coding agents.
// Build: v .   (→ bin/vrepo)    Run: vrepo [root]   (default: .)
module main

import os
import vrepo

fn main() {
	root := if os.args.len > 1 { os.args[1] } else { '.' }
	out := vrepo.brief(root, vrepo.Budget{}) or {
		eprintln('vrepo: ${err.msg()}')
		exit(1)
	}
	print(out)
}
