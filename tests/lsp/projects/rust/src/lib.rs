/// One step, used by both the authored block and named-reference probe.
pub fn step(n: u64) -> u64 { n + 1 }

// Authored block. The emoji tests UTF-16 positions before the reference.
pub fn example() -> u64 { /* 😀 */ step(2) }

// A named reference in the same crate and scope as the authored block.
fn reference_probe() { let _ = step; }
