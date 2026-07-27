#!/usr/bin/env bash

set -euo pipefail

JULIA_BIN="${JULIA_BIN:-julia}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OLD_SNOW_DIR="${OLD_SNOW_DIR:-$REPO_DIR/../SNOW_old_color_bench}"
OLD_COMMIT="${OLD_SNOW_COMMIT:-}"
MODE="${MODE:-both}"

usage() {
    cat <<'USAGE'
Usage:
  ./benchmark/run.sh [--old COMMIT] [ad|fd|both]

Without --old, benchmark the current checkout only.  --old adds an optional
comparison against a checkout at the given git commit.

Environment:
  JULIA_BIN: Julia executable (default: julia)
  OLD_SNOW_DIR: old checkout path (default: ../SNOW_old_color_bench)
  OLD_SNOW_COMMIT: old commit; equivalent to --old COMMIT
  BENCH_NSAMPLES: BenchmarkTools samples (default: 2000)
  BENCH_NEVALS: evaluations per sample (default: 1)
  BENCH_ALGORITHMS: comma-separated current algorithms

Examples:
  ./benchmark/run.sh
  ./benchmark/run.sh --old 66d0297 both
  OLD_SNOW_COMMIT=66d0297 ./benchmark/run.sh fd
USAGE
}

if ! command -v "$JULIA_BIN" >/dev/null 2>&1; then
    echo "Julia not found: set JULIA_BIN to a Julia executable path" >&2
    exit 1
fi

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
        ad|fd|both)
            MODE="$1"
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

BENCH_NSAMPLES="${BENCH_NSAMPLES:-2000}"
BENCH_NEVALS="${BENCH_NEVALS:-1}"
BENCH_ALGORITHMS="${BENCH_ALGORITHMS:-greedy,greedy_smallest_last,greedy_largest_first,constant}"
BENCH_TMP_ROOT="$(mktemp -d -t snow-color-bench-XXXXXX)"
trap 'rm -rf "$BENCH_TMP_ROOT"' EXIT

build_bench_env() {
    local env_dir="$1"
    local snow_dir="$2"

    mkdir -p "$env_dir"
    "$JULIA_BIN" --project="$env_dir" -e '
        using Pkg
        Pkg.activate(ARGS[1]; shared = false)
        Pkg.develop(path = ARGS[2])
        Pkg.add("BenchmarkTools")
        Pkg.instantiate()
        Pkg.precompile()
    ' "$env_dir" "$snow_dir"
}

run_bench() {
    local label="$1"
    local env_dir="$2"
    local algorithms="$3"

    echo "----- $label -----"
    BENCH_MODE="$MODE" BENCH_ALGORITHMS="$algorithms" \
        BENCH_NSAMPLES="$BENCH_NSAMPLES" BENCH_NEVALS="$BENCH_NEVALS" \
        "$JULIA_BIN" --project="$env_dir" -e \
        'include(ARGS[1]); results = BenchmarkTools.run(SUITE; verbose = true); function print_results(group, pad = ""); for (id, result) in group; if result isa BenchmarkTools.BenchmarkGroup; println(pad, id, ":"); print_results(result, pad * "  "); else; print(pad, id, ": "); show(stdout, MIME"text/plain"(), result); println(); end; end; end; print_results(results)' \
        "$SCRIPT_DIR/benchmarks.jl"
}

build_bench_env "$BENCH_TMP_ROOT/current" "$REPO_DIR"
run_bench "SNOW current" "$BENCH_TMP_ROOT/current" "$BENCH_ALGORITHMS"

if [ -n "$OLD_COMMIT" ]; then
    expected_old_head="$(git -C "$REPO_DIR" rev-parse "$OLD_COMMIT^{commit}")"
    if [ -e "$OLD_SNOW_DIR/.git" ]; then
        old_head="$(git -C "$OLD_SNOW_DIR" rev-parse HEAD)"
        if [ "$old_head" != "$expected_old_head" ]; then
            echo "Existing old checkout is at $old_head, expected $expected_old_head" >&2
            exit 1
        fi
    else
        git -C "$REPO_DIR" worktree add "$OLD_SNOW_DIR" "$OLD_COMMIT"
    fi

    build_bench_env "$BENCH_TMP_ROOT/old" "$OLD_SNOW_DIR"
    run_bench "SNOW old ($expected_old_head)" "$BENCH_TMP_ROOT/old" legacy
fi
