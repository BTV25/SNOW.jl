#!/usr/bin/env bash

set -euo pipefail

JULIA_BIN="${JULIA_BIN:-julia}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    cat <<'USAGE'
Usage:
  ./benchmark/run.sh [--old COMMIT]

Runs benchmark/sparse_jacobian_bench.jl against the current checkout.  With
--old, also runs it against a checkout at the given git commit (e.g. master),
via a temporary git worktree, so the two can be compared side by side. This
is useful for older commits that predate the benchmark/ directory itself,
since the current script + Project.toml are copied over rather than assumed
to already exist there.

Environment:
  JULIA_BIN: Julia executable (default: julia)

Examples:
  ./benchmark/run.sh
  ./benchmark/run.sh --old 66d0297
USAGE
}

OLD_COMMIT=""
while (($#)); do
    case "$1" in
        --old)
            (($# >= 2)) || { echo "--old requires a commit" >&2; usage; exit 1; }
            OLD_COMMIT="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if ! command -v "$JULIA_BIN" >/dev/null 2>&1; then
    echo "Julia not found: set JULIA_BIN to a Julia executable path" >&2
    exit 1
fi

BENCH_TMP_ROOT="$(mktemp -d -t snow-bench-XXXXXX)"
trap 'rm -rf "$BENCH_TMP_ROOT"' EXIT

build_bench_env() {
    local env_dir="$1"
    local snow_dir="$2"

    mkdir -p "$env_dir"
    cp "$SCRIPT_DIR/sparse_jacobian_bench.jl" "$env_dir/"
    "$JULIA_BIN" --project="$env_dir" -e '
        using Pkg
        Pkg.activate(ARGS[1]; shared = false)
        Pkg.develop(path = ARGS[2])
        for dep in ("BenchmarkTools", "MatrixDepot", "Random", "SparseArrays")
            Pkg.add(dep)
        end
        Pkg.instantiate()
        Pkg.precompile()
    ' "$env_dir" "$snow_dir"
}

run_bench() {
    local label="$1"
    local env_dir="$2"

    echo "----- $label -----"
    "$JULIA_BIN" --project="$env_dir" "$env_dir/sparse_jacobian_bench.jl"
}

build_bench_env "$BENCH_TMP_ROOT/current" "$REPO_DIR"
run_bench "SNOW current ($(git -C "$REPO_DIR" rev-parse --short HEAD))" "$BENCH_TMP_ROOT/current"

if [ -n "$OLD_COMMIT" ]; then
    OLD_SNOW_DIR="$BENCH_TMP_ROOT/old-checkout"
    expected_old_head="$(git -C "$REPO_DIR" rev-parse "$OLD_COMMIT^{commit}")"
    git -C "$REPO_DIR" worktree add "$OLD_SNOW_DIR" "$OLD_COMMIT" >/dev/null
    trap 'git -C "$REPO_DIR" worktree remove "$OLD_SNOW_DIR" --force >/dev/null 2>&1; rm -rf "$BENCH_TMP_ROOT"' EXIT

    build_bench_env "$BENCH_TMP_ROOT/old" "$OLD_SNOW_DIR"
    run_bench "SNOW old ($expected_old_head)" "$BENCH_TMP_ROOT/old"
fi
