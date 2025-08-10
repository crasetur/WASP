use anyhow::Result;
#[no_mangle]
pub extern "C" fn plugin_entry() { let _ = run(); }
pub fn run() -> Result<()> { Ok(()) }
