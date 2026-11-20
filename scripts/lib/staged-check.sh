#!/bin/sh
# Shared staged-index export runner for pre-commit checks.
# Exports staged blobs, config, helper libs, and the staged check script into a
# private temporary directory so commits (including `commit -a`, `commit <path>`,
# and partial hunks) are judged strictly on what enters git history.

STAGED_CHECK_TMP_PREFIX='ajans-staged-check'

# Usage:
#   run_staged_check <label> <config_path> <runner_path> -- <pathspec... | --from-runner>
run_staged_check() {
  sc_label=$1
  sc_config=$2
  sc_runner=$3
  shift 3
  if [ "${1:-}" != "--" ]; then
    echo "error: run_staged_check requires '--' before pathspecs" >&2
    exit 1
  fi
  shift

  # Verify every required config/helper file is a tracked regular file in the
  # index before any fast exit, so deleting or symlinking one always fails closed.
  for sc_req in \
    "$sc_config" mise.toml "$sc_runner" \
    scripts/lib/tool-pin.sh scripts/lib/staged-check.sh; do
    case "$(staged_git ls-files -s -- "$sc_req")" in
    100644\ * | 100755\ *) ;;
    *)
      echo "error: $sc_req must be a tracked regular file in the index; cannot run $sc_label" >&2
      exit 1
      ;;
    esac
  done

  # Match pre-push's direct ./scripts/... execution by failing if the staged
  # runner lost its executable bit.
  case "$(staged_git ls-files -s -- "$sc_runner")" in
  100755\ *) ;;
  *)
    echo "error: $sc_runner must be executable (mode 100755) in the index" >&2
    exit 1
    ;;
  esac

  # Subshell isolates the cleanup trap and `set -f` from the calling hook.
  (
    set -eu
    set -f
    sc_tmp=$(mktemp -d "${TMPDIR:-/tmp}/${STAGED_CHECK_TMP_PREFIX}.XXXXXX")
    # Only the mktemp directory this run created, never a computed parent.
    trap 'case "${sc_tmp:-}" in */"${STAGED_CHECK_TMP_PREFIX}".*) rm -rf -- "$sc_tmp" ;; esac' EXIT INT TERM HUP
    MISE_IGNORED_CONFIG_PATHS="${MISE_IGNORED_CONFIG_PATHS:+$MISE_IGNORED_CONFIG_PATHS:}$sc_tmp"
    export MISE_IGNORED_CONFIG_PATHS

    if [ "${1:-}" = "--from-runner" ]; then
      printf '%s\n' "$sc_runner" | staged_git checkout-index --force --stdin --prefix="$sc_tmp/"
      sc_spec_list=$("$sc_tmp/$sc_runner" --pathspecs)
      set --
      while IFS= read -r sc_spec; do
        [ -n "$sc_spec" ] || continue
        set -- "$@" "$sc_spec"
      done <<EOF
$sc_spec_list
EOF
    fi

    # No --diff-filter here: changing or deleting a config, pin, or helper
    # script must re-check every tracked target in the index.
    if staged_git diff --cached --quiet -- \
      "$sc_config" mise.toml "$sc_runner" 'scripts/lib/*'; then
      # --no-renames splits renames into D+A so ACM catches new destinations;
      # filtering mode to 100644/100755 excludes staged symlinks (120000).
      sc_files=$(staged_git diff --cached --raw --no-renames --diff-filter=ACM -- "$@" |
        awk -F '\t' '$1 ~ /^:[0-7]+ (100644|100755) / { print $2 }')
    else
      sc_files=$(staged_git ls-files -s -- "$@" |
        awk -F '\t' '$1 ~ /^(100644|100755) / { print $2 }')
    fi
    [ -n "$sc_files" ] || exit 0

    sc_libs=$(staged_git ls-files -s -- 'scripts/lib/*' |
      awk -F '\t' '$1 ~ /^(100644|100755) / { print $2 }')

    {
      printf '%s\n' "$sc_config" mise.toml "$sc_runner"
      [ -z "$sc_libs" ] || printf '%s\n' "$sc_libs"
      printf '%s\n' "$sc_files"
    } | staged_git checkout-index --force --stdin --prefix="$sc_tmp/"

    for sc_req in \
      "$sc_config" mise.toml "$sc_runner" \
      scripts/lib/tool-pin.sh scripts/lib/staged-check.sh; do
      if [ ! -f "$sc_tmp/$sc_req" ] || [ -L "$sc_tmp/$sc_req" ] || [ ! -s "$sc_tmp/$sc_req" ]; then
        echo "error: staged $sc_req is missing or empty; cannot run $sc_label" >&2
        exit 1
      fi
    done

    echo "pre-commit: $sc_label (staged; paths under $sc_tmp)"
    set --
    while IFS= read -r sc_f; do
      [ -n "$sc_f" ] || continue
      set -- "$@" "$sc_tmp/$sc_f"
    done <<EOF
$sc_files
EOF

    "$sc_tmp/$sc_runner" -- "$@"
  )
}
