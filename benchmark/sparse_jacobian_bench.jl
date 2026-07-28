#=
Benchmark comparing sparse-Jacobian cache construction and evaluation cost,
across all four differentiation methods (AD, forward/central FD, complex
step). Run this same script against different commits/branches to compare
them - see benchmark/README.md.

    julia --project=benchmark benchmark/sparse_jacobian_bench.jl
=#

using SNOW, SparseArrays, BenchmarkTools, Printf

# ---------------------------------------------------------------------------
# synthetic problems spanning coloring difficulty
# ---------------------------------------------------------------------------

function tridiagonal!(g, x)
    n = length(x)
    g[1] = x[1]^2 - 2x[2]
    for i in 2:n-1
        g[i] = x[i-1]*x[i] - x[i+1]^2 + sin(x[i])
    end
    g[n] = x[n]^2 - x[n-1]
    return sum(abs2, x)
end

function laplacian2d!(g, x, m)
    idx(i, j) = (i - 1) * m + j
    for i in 1:m, j in 1:m
        k = idx(i, j)
        c = 4x[k]
        c -= i > 1 ? x[idx(i-1,j)] : 0.0
        c -= i < m ? x[idx(i+1,j)] : 0.0
        c -= j > 1 ? x[idx(i,j-1)] : 0.0
        c -= j < m ? x[idx(i,j+1)] : 0.0
        g[k] = c + 0.01*x[k]^3
    end
    return sum(abs2, x)
end

# worst case for forward-mode coloring: g[1] depends on every x[i], so every
# column conflicts with every other column -> ncolors == nx
function starfun!(g, x)
    n = length(x)
    g[1] = sum(x)
    for i in 2:n
        g[i] = x[i]^2 + 0.1*x[1]
    end
    return sum(abs2, x)
end

# non-square (overdetermined): more constraints than variables
function overdetermined!(g, x)
    nx = length(x)
    ng = length(g)
    for i in 1:ng
        j1 = ((i - 1) % nx) + 1
        j2 = (i % nx) + 1
        g[i] = 0.3*x[j1]^2 + (j2 != j1 ? 0.2*x[j2] : 0.0)
    end
    return sum(abs2, x)
end

problems = [
    ("tridiagonal_n2000", tridiagonal!, 2000, 2000),
    ("laplacian2d_n3600", (g, x) -> laplacian2d!(g, x, 60), 3600, 3600),
    ("arrowhead_n500", starfun!, 500, 500),
    ("nonsquare_nx2000_ng5000", overdetermined!, 2000, 5000),
]

# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------

methods = [
    ("AD", ForwardAD()),
    ("FD-forward", ForwardFD()),
    ("FD-central", CentralFD()),
    ("CS", ComplexStep()),
]

println(@sprintf("%-24s %-11s %8s %8s %10s | %12s %12s %10s",
    "problem", "method", "nx", "ng", "nnz", "cache setup", "eval", "eval bytes"))
println(repeat("-", 100))

for (name, f!, nx, ng) in problems
    lx = -5.0*ones(nx)
    ux = 5.0*ones(nx)
    sp = SparsePattern(ForwardAD(), f!, ng, lx, ux)
    x = collect(range(0.13, 1.87, length=nx))

    for (mname, dtype) in methods
        t_setup = @belapsed SNOW.sparsejacobiancache($sp, $dtype, $f!, $nx, $ng) samples=20 evals=1
        cache = SNOW.sparsejacobiancache(sp, dtype, f!, nx, ng)
        dg = zeros(length(sp.rows))
        t_eval = @belapsed SNOW.sparsejacobian!($dg, $x, $cache) samples=10 evals=1
        b_eval = @ballocated SNOW.sparsejacobian!($dg, $x, $cache) samples=10 evals=1

        println(@sprintf("%-24s %-11s %8d %8d %10d | %10.3fms %10.3fms %10dB",
            name, mname, nx, ng, length(sp.rows), t_setup*1e3, t_eval*1e3, b_eval))
    end
end
