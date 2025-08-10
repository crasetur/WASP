#!/usr/bin/env bash
set -euo pipefail

echo "🔧 Bootstrapping Cargo workspace + CI"

ROOT_DIR="."
ROOT_TOML="$ROOT_DIR/Cargo.toml"
BACKUP_SUFFIX="$(date +%Y%m%d-%H%M%S)"

mapfile -t HOSTS < <(find "$ROOT_DIR" -type f -path "*/src/main.rs" 2>/dev/null | sed 's#/src/main.rs##' | sort -u)
mapfile -t TOMLS < <(find "$ROOT_DIR" -name Cargo.toml 2>/dev/null | sort)
PLUGIN_DIRS=()
for t in "${TOMLS[@]}"; do
  if grep -q "^\[lib\]" "$t" 2>/dev/null && grep -qi 'crate-type.*cdylib' "$t" 2>/dev/null; then
    PLUGIN_DIRS+=("$(dirname "$t")")
  fi
done

echo "📦 Hosts found : ${#HOSTS[@]}"
printf '  - %s\n' "${HOSTS[@]}" || true
echo "🧩 Plugins (cdylib): ${#PLUGIN_DIRS[@]}"
printf '  - %s\n' "${PLUGIN_DIRS[@]}" || true

MEMBERS=()
for h in "${HOSTS[@]}"; do
  rel="$(realpath --relative-to="$ROOT_DIR" "$h" 2>/dev/null || echo "$h")"
  MEMBERS+=("$rel")
done
for p in "${PLUGIN_DIRS[@]}"; do
  rel="$(realpath --relative-to="$ROOT_DIR" "$p" 2>/dev/null || echo "$p")"
  MEMBERS+=("$rel")
done
mapfile -t MEMBERS < <(printf "%s\n" "${MEMBERS[@]}" | awk 'NF' | sort -u)

if [ ${#MEMBERS[@]} -eq 0 ]; then
  echo "⚠️  No host/plugin found. Will create an empty workspace."
fi

if [ -f "$ROOT_TOML" ]; then
  cp -f "$ROOT_TOML" "$ROOT_TOML.$BACKUP_SUFFIX.bak"
  echo "🗂️  Backup created: $ROOT_TOML.$BACKUP_SUFFIX.bak"
fi

cat > "$ROOT_TOML" <<'TOML'
[workspace]
resolver = "2"
members = [
  # __AUTO_MEMBERS__
]

[workspace.package]
edition = "2021"
license = "MIT OR Apache-2.0"

[workspace.dependencies]
anyhow = "1"
log = "0.4"
env_logger = "0.11"
TOML

if [ ${#MEMBERS[@]} -gt 0 ]; then
  MEMBERS_LINES=$(printf '  "%s",\n' "${MEMBERS[@]}")
else
  MEMBERS_LINES=''
fi
tmpfile="$(mktemp)"
awk -v repl="$MEMBERS_LINES" '
  { 
    if ($0 ~ /#__AUTO_MEMBERS__/) { 
      gsub(/# __AUTO_MEMBERS__/, repl); print; next 
    } 
  }1
' "$ROOT_TOML" > "$tmpfile"
mv "$tmpfile" "$ROOT_TOML"

echo "✅ Workspace written to $ROOT_TOML"
echo "   Members:"
printf '   - %s\n' "${MEMBERS[@]}" || true

if [ ! -f ".gitignore" ]; then
cat > .gitignore <<'GIT'
/target
Cargo.lock
node_modules
dist
.DS_Store
**/*.rs.bk
GIT
  echo "🧹 .gitignore created."
fi

CIYML=".github/workflows/ci.yml"
if [ ! -f "$CIYML" ]; then
  mkdir -p .github/workflows
  cat > "$CIYML" <<'YML'
name: CI
on:
  push:
  pull_request:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          targets: wasm32-unknown-unknown
      - uses: actions/cache@v4
        with:
          path: |
            ~/.cargo/bin/
            ~/.cargo/registry/index/
            ~/.cargo/registry/cache/
            ~/.cargo/git/db/
            target/
          key: ${{ runner.os }}-cargo-${{ hashFiles('**/Cargo.lock') }}
          restore-keys: ${{ runner.os }}-cargo-
      - name: Build workspace
        run: cargo build --workspace --verbose
      - name: Build WASM (all cdylib plugins)
        run: |
          rustup target add wasm32-unknown-unknown
          for t in $(git ls-files | grep Cargo.toml); do
            if grep -q "^\[lib\]" "$t" && grep -qi 'crate-type.*cdylib' "$t"; then
              crate_dir=$(dirname "$t")
              crate_name=$(basename "$crate_dir")
              echo "==> Building $crate_name (WASM)"
              cargo build -p "$crate_name" --target wasm32-unknown-unknown --release || exit 1
            fi
          done
      - name: Setup Node
        if: ${{ hashFiles('**/package.json') != '' }}
        uses: actions/setup-node@v4
        with:
          node-version: '20'
      - name: Cache Node
        if: ${{ hashFiles('**/package.json') != '' }}
        uses: actions/cache@v4
        with:
          path: |
            **/node_modules
          key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json', '**/pnpm-lock.yaml', '**/yarn.lock') }}
          restore-keys: ${{ runner.os }}-node-
      - name: Install deps (Node)
        if: ${{ hashFiles('**/package.json') != '' }}
        run: |
          if [ -f package-lock.json ]; then npm ci; else npm i; fi
      - name: Lint (JS)
        if: ${{ hashFiles('**/.eslintrc*') != '' }}
        run: npx eslint . || true
YML
  echo "🤖 CI created: $CIYML"
else
  echo "ℹ️  CI already exists: $CIYML (skipped)"
fi

echo "🎉 Done. Build locally with:"
echo "    rustup target add wasm32-unknown-unknown"
echo "    cargo build --workspace --verbose"
