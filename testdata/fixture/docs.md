module main

# fake docs with a stray main declaration — vrepo must NOT list this as an
# entry point; only real .v/.vsh files qualify.

```v
fn main() {
	println('this is documentation, not an entry point')
}
```
