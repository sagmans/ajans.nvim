#!/bin/sh
# Shared pinned-tool lookup and version verification for repo check scripts.
# Keeps tool version enforcement fail-closed and sourced from mise.toml where
# mise manages the tool, avoiding duplicated version checks across scripts.

parse_mise_pin() {
  tool=$1
  mise_file=$2
  if [ ! -f "$mise_file" ]; then
    echo "error: missing $mise_file; cannot verify pinned $tool version" >&2
    exit 1
  fi
  # Scope pin lookup strictly to [tools] and fail closed on duplicates.
  pin=$(awk -v key="$tool" '
    /^\[/ { in_tools = ($0 ~ /^\[tools\][[:space:]]*(#.*)?$/); next }
    in_tools {
      line = $0
      sub(/[[:space:]]*#.*/, "", line)
      if (line ~ "^\"?" key "\"?[[:space:]]*=[[:space:]]*\"[0-9]+\\.[0-9]+\\.[0-9]+\"[[:space:]]*$") {
        sub(/^[^=]*=[[:space:]]*"/, "", line)
        sub(/".*$/, "", line)
        val = line
        count++
      }
    }
    END { if (count == 1) print val }
  ' "$mise_file")
  if [ -z "$pin" ]; then
    echo "error: no exact $tool pin found in [tools] of $mise_file" >&2
    exit 1
  fi
  printf '%s\n' "$pin"
}

resolve_mise_pins() {
  if ! command -v mise >/dev/null 2>&1 || [ "$#" -eq 0 ]; then
    return 0
  fi
  # Prepend exact tool@version install dirs so mise-pinned binaries take
  # precedence over Homebrew or shims; require_pinned_tool still fails closed.
  pin_paths=$(mise bin-paths "$@" 2>/dev/null | paste -sd: -) || pin_paths=''
  if [ -n "$pin_paths" ]; then
    PATH="$pin_paths:$PATH"
    export PATH
  fi
}

require_pinned_tool() {
  bin=$1
  expected=$2
  sed_expr=$3
  hint=$4
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "error: $bin not found; $hint" >&2
    exit 1
  fi
  # Capture --version before sed so a failing binary or broken shim fails closed.
  if raw=$("$bin" --version 2>/dev/null); then
    actual=$(printf '%s\n' "$raw" | sed -n "$sed_expr" | sed -n '1p')
  else
    actual=''
  fi
  if [ "$actual" != "$expected" ]; then
    echo "error: $bin version mismatch: expected $expected, got ${actual:-missing}; $hint" >&2
    exit 1
  fi
}

require_mise_tool() {
  bin=$1
  mise_key=$2
  mise_file=$3
  sed_expr=$4
  version=$(parse_mise_pin "$mise_key" "$mise_file")
  resolve_mise_pins "${mise_key}@${version}"
  require_pinned_tool "$bin" "$version" "$sed_expr" \
    "install $bin $version (mise install)"
}
