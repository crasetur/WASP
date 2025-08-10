use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub fn run(input: &str) -> String {
    format!("ok: {input}")
}
