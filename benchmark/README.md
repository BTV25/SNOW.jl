# Benchmarks

Run the current benchmark suite with:

```bash
./benchmark/run.sh
```

To compare with an older checkout, provide its commit hash:

```bash
./benchmark/run.sh --old 66d0297 both
```

The benchmark definitions are in [`benchmarks.jl`](benchmarks.jl), and the
benchmark environment is defined in [`Project.toml`](Project.toml).

The runner prints the full timing summary for every derivative mode and
coloring-algorithm permutation.

## Real-world sparse Jacobian benchmark

[`sparse_jacobian_bench.jl`](sparse_jacobian_bench.jl) complements the above
with a handful of synthetic problems (tridiagonal, 2D Laplacian, worst-case
coloring, non-square) benchmarked across all four differentiation methods
(AD, forward/central FD, complex step):

```bash
julia --project=benchmark benchmark/sparse_jacobian_bench.jl
```
