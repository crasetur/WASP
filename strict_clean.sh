#!/usr/bin/env bash
set -euo pipefail

Q=".quarantine_strict"
mkdir -p "$Q"

echo "== Strict clean start =="

# --- 1) Keep only .github/workflows/ci.yml ---
if [ -d ".github/workflows" ]; then
  echo "-- Workflows: keep only ci.yml"
  shopt -s nullglob
  for f in .github/workflows/*.{yml,yaml}; do
    base="$(basename "$f")"
    if [ "$base" != "ci.yml" ]; then
      mkdir -p "$Q/.github/workflows"
      mv "$f" "$Q/.github/workflows/"
      git rm -f --quiet "$f" || true
      echo "   removed: $f"
    fi
  done
  shopt -u nullglob
fi

# Helper: enforce a file to exist only at repo root (./NAME)
enforce_root_only () {
  local name="$1"
  echo "-- Enforce root-only: $name"
  # find all matching basenames
  mapfile -t hits < <(git ls-files | awk -v n="$name" -F'\n' '{print}' | grep -E "/?$name$" || true)

  # If not tracked, also look on disk (untracked)
  if [ ${#hits[@]} -eq 0 ]; then
    mapfile -t hits < <(find . -type f -name "$name" ! -path "*/.git/*" || true)
  fi

  # Keep ./name, move others
  for p in "${hits[@]}"; do
    # normalise path
    p="${p#./}"
    if [ "$p" = "$name" ]; then
      echo "   keep: ./$p"
      continue
    fi
    # quarantine & remove
    dest="$Q/${p%/*}"
    mkdir -p "$dest"
    mv "$p" "$dest/"
    git rm -f --quiet "$p" || true
    echo "   removed: ./$p"
  done
}

# --- 2) Root-only files ---
enforce_root_only "bootstrap_workspace.sh"
enforce_root_only "package.json"
enforce_root_only "index.js"

# --- 3) (Optional) strict dedupe others by identical content
if [[ "${STRICT_ALL:-0}" = "1" ]]; then
  echo "-- Extra: remove identical-content duplicates (scripts/workflows)"
  mapfile -t FILES < <(find . -type f \( -name "*.sh" -o -name "*.js" -o -name "*.mjs" -o -name "*.cjs" -o -name "*.yml" -o -name "*.yaml" \) \
    ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "$Q/*" | sort)
  declare -A keep_for_sha
  for f in "${FILES[@]}"; do
    sha="$(sha1sum "$f" | awk '{print $1}')"
    if [[ -z "${keep_for_sha[$sha]:-}" ]]; then
      keep_for_sha[$sha]="$f"
      continue
    fi
    # already have a keeper; move this
    dest="$Q/${f%/*}"
    mkdir -p "$dest"
    mv "$f" "$dest/"
    git rm -f --quiet "$f" || true
    echo "   dedup removed: $f"
  done
fi

echo "== Done =="
echo "Quarantined files in: $Q"
echo "Review with: git status && ls -la $Q"
