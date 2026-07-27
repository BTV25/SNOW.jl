# Benchmarks

Run the sparse-Jacobian benchmark against the current checkout with:

```bash
julia --project=benchmark benchmark/sparse_jacobian_bench.jl
```

To also compare against an older commit (e.g. `master`), use `run.sh`, which
builds a throwaway environment for each side and runs the same script in
both, via a temporary git worktree for the old commit:

```bash
./benchmark/run.sh --old 66d0297
```

See `benchmark/sparse_jacobian_bench.jl` for the problem set (synthetic
sparsity patterns plus real-world matrices from the SuiteSparse Matrix
Collection via MatrixDepot.jl).
