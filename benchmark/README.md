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
