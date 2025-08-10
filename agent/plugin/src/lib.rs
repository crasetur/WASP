#[inline]
pub fn add_pure(a: i32, b: i32) -> i32 { a + b }

#[no_mangle]
pub extern "C" fn run() { }

#[no_mangle]
pub extern "C" fn add(a: i32, b: i32) -> i32 { add_pure(a, b) }

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn test_add_pure() { assert_eq!(add_pure(2, 40), 42); }
}
