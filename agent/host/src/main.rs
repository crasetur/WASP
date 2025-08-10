use anyhow::Result;

fn main() -> Result<()> {
    println!("Host starting…");

    let wasm_path = "host/src/agent_template.wasm";
    if std::path::Path::new(wasm_path).exists() {
        println!("Loading WASM: {wasm_path}");
        run_wasm(wasm_path)?;
    } else {
        println!("(skip) {wasm_path} not found. Build plugin first.");
    }

    Ok(())
}

fn run_wasm(path: &str) -> Result<()> {
    use wasmtime::{Engine, Instance, Module, Store};

    let engine = Engine::default();
    let module = Module::from_file(&engine, path)?;
    let mut store = Store::new(&engine, ());
    let instance = Instance::new(&mut store, &module, &[])?;

    let add = instance.get_typed_func::<(i32, i32), i32>(&mut store, "add")?;
    let result = add.call(&mut store, (2, 40))?;
    println!("Plugin add(2, 40) = {result}");
    Ok(())
}
