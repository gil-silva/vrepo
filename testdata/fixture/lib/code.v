const answer = 42

pub struct Point {
pub:
	x int
	y int
}

pub fn add_vals(a int, b int) int {
	return a + b
}

fn internal_helper() {
	// not outlined: lower visibility, still listed
}

pub fn (p Point) hypot() f64 {
	// method receiver goes to the method outline
	return f64(p.x * p.x + p.y * p.y)
}
