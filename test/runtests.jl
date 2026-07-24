using SNOW
using Test
using Zygote
using BenchmarkTools

checkallocations = false
snopttest = false

@testset "derivatives" begin

function test1!(g, x)

    f = x[1]^2 - x[2]

    # Zygote.ignore() do
    g[1] = x[2] - 2*x[1]
    g[2] = -x[2]
    g[3] = x[1]^2
    # end
    return f
end

# ---- test sparsity pattern  --------
ng = 3
lx = [-5; -5]
ux = [5; 5]
sp = SparsePattern(ForwardAD(), test1!, ng, lx, ux)
@test sp.rows == [1, 3, 1, 2]
@test sp.cols == [1, 1, 2, 2]
# -------------------------------------

# ----- test derivatives ------------
nx = 2
ng = 3
g = zeros(ng)
df = zeros(nx)
dg = zeros(ng*nx)
x = [1.0, 2.0]

# forward AD
cache = SNOW.createcache(DensePattern(), ForwardAD(), test1!, nx, ng)
SNOW.evaluate!(g, df, dg, x, cache)

@test df == [2*x[1]; -1.0]
@test dg == [-2.0, 0.0, 2*x[1], 1.0, -1.0, 0.0]

# reverse AD
cache = SNOW.createcache(DensePattern(), ReverseAD(), test1!, nx, ng)
SNOW.evaluate!(g, df, dg, x, cache)
@test df == [2*x[1]; -1.0]
@test dg == [-2.0, 0.0, 2*x[1], 1.0, -1.0, 0.0]

# finite diff
cache = SNOW.createcache(DensePattern(), ForwardFD(), test1!, nx, ng)
SNOW.evaluate!(g, df, dg, x, cache)

@test isapprox(df, [2*x[1]; -1.0])
@test isapprox(dg, [-2.0, 0.0, 2*x[1], 1.0, -1.0, 0.0])

# sparse with reverse and forward
dg = zeros(length(sp.rows))
cache = SNOW.createcache(sp, [ReverseAD(), ForwardAD()], test1!, nx, ng)
SNOW.evaluate!(g, df, dg, x, cache)

@test df == [2*x[1]; -1.0]
@test dg == [-2.0, 2*x[1], 1.0, -1.0]

# sparse with reverse and finite-difference
for fd in (ForwardFD(), CentralFD(), ComplexStep())
    dg = zeros(length(sp.rows))
    cache = SNOW.createcache(sp, [ReverseAD(), fd], test1!, nx, ng)
    SNOW.evaluate!(g, df, dg, x, cache)

    @test isapprox(df, [2*x[1]; -1.0])
    @test isapprox(dg, [-2.0, 2*x[1], 1.0, -1.0])
end

function benchstats(g, df, dg, x, cache)
    bench = @benchmark SNOW.evaluate!($g, $df, $dg, $x, $cache) samples=2000
    t = sort(Float64.(bench.times) ./ 1e3)
    n = length(t)
    return (
        n = n,
        min = t[1],
        median = t[cld(n, 2)],
        p90 = t[clamp(Int(ceil(0.90 * n)), 1, n)],
        p95 = t[clamp(Int(ceil(0.95 * n)), 1, n)],
        p99 = t[clamp(Int(ceil(0.99 * n)), 1, n)],
        max = t[end],
    )
end

bench_median_reference_us = (
    ad = (n = 2000, min = 1.0, median = 1.125, p90 = 1.167, p95 = 1.208, p99 = 1.25, max = 18.292),
    fd = (n = 2000, min = 0.959, median = 1.084, p90 = 1.167, p95 = 1.167, p99 = 1.25, max = 15.5),
    cd = (n = 2000, min = 1.0, median = 1.084, p90 = 1.166, p95 = 1.167, p99 = 1.25, max = 20.583),
    cs = (n = 2000, min = 0.958, median = 1.042, p90 = 1.125, p95 = 1.125, p99 = 1.208, max = 15.416),
)

bench_median_limits_us = (
    ad = 2 * bench_median_reference_us.ad.median,
    fd = 2 * bench_median_reference_us.fd.median,
    cd = 2 * bench_median_reference_us.cd.median,
    cs = 2 * bench_median_reference_us.cs.median,
)

function assert_benchstats(stats, max_median)
    @test stats.n > 0
    @test stats.min > 0
    @test stats.min <= stats.median <= stats.p90 <= stats.p95 <= stats.p99 <= stats.max
    @test stats.median <= max_median
end

function assert_runtime_order(stats_ad, stats_fd, stats_cd, stats_cs)
    # keep comparisons loose enough for shared CI nodes but still catch regressions
    @test stats_ad.median * 50 >= stats_fd.median
    @test stats_ad.median * 50 >= stats_cd.median
    @test stats_ad.median * 50 >= stats_cs.median
end

sparse_bench_ad = benchstats(g, df, dg, x, SNOW.createcache(sp, [ReverseAD(), ForwardAD()], test1!, nx, ng))
sparse_bench_fd = benchstats(g, df, dg, x, SNOW.createcache(sp, [ReverseAD(), ForwardFD()], test1!, nx, ng))
sparse_bench_cd = benchstats(g, df, dg, x, SNOW.createcache(sp, [ReverseAD(), CentralFD()], test1!, nx, ng))
sparse_bench_cs = benchstats(g, df, dg, x, SNOW.createcache(sp, [ReverseAD(), ComplexStep()], test1!, nx, ng))
assert_benchstats(sparse_bench_ad, bench_median_limits_us.ad)
assert_benchstats(sparse_bench_fd, bench_median_limits_us.fd)
assert_benchstats(sparse_bench_cd, bench_median_limits_us.cd)
assert_benchstats(sparse_bench_cs, bench_median_limits_us.cs)
assert_runtime_order(sparse_bench_ad, sparse_bench_fd, sparse_bench_cd, sparse_bench_cs)

# # sparse with zygote and forward
# dg = zeros(length(sp.rows))
# cache = SNOW.createcache(sp, [RevZyg(), ForwardAD()], test1!, nx, ng)
# SNOW.evaluate!(g, df, dg, x, cache)

# @test df == [2*x[1]; -1.0]
# @test dg == [-2.0, 2*x[1], 1.0, -1.0]

# ----------------------------------------

end

# if checkallocations
# # -------- test allocations --------------
#     using BenchmarkTools

#     function test2!(g, x)
#         f = x[1]^2 - x[2]
        
#         Zygote.ignore() do
#             nx = length(x)
#             for i = 1:nx
#                 g[i] = x[i]^2
#             end
#             g[nx+1:end] .= x[1]
#         end
#         return f
#     end

#     nx = 300
#     ng = 500
#     g = zeros(ng)
#     df = zeros(nx)
#     dg = zeros(ng*nx)
#     x = 2*ones(nx)
#     cache = SNOW.createcache(DensePattern(), ForwardAD(), test2!, nx, ng)
#     @btime SNOW.evaluate!($g, $df, $dg, $x, $cache)
#     # 577.123 μs (6 allocations: 2.30 MiB)

#     cache = SNOW.createcache(DensePattern(), ReverseAD(), test2!, nx, ng)
#     @btime SNOW.evaluate!($g, $df, $dg, $x, $cache)
#     # 4.188 ms (6 allocations: 2.30 MiB)

#     cache = SNOW.createcache(DensePattern(), FD("forward"), test2!, nx, ng)
#     @btime SNOW.evaluate!($g, $df, $dg, $x, $cache)
#     # 358.457 μs (6 allocations: 2.30 MiB)

#     lx = -5*ones(nx)
#     ux = 5*ones(nx)
#     sp = SparsePattern(ForwardAD(), test2!, ng, lx, ux)
#     dg = zeros(length(sp.rows))
#     cache = SNOW.createcache(sp, [ReverseAD(), ForwardAD()], test2!, nx, ng)
#     @btime SNOW.evaluate!($g, $df, $dg, $x, $cache)
#     # 17.391 μs (0 allocations: 0 bytes)

#     cache = SNOW.createcache(sp, [RevZyg(), ForwardAD()], test2!, nx, ng)
#     @btime SNOW.evaluate!($g, $df, $dg, $x, $cache)
#     # 9.865 μs (6 allocations: 11.63 KiB)
# end
# # ----------------------------------------


@testset "optimization" begin

function barnes(g, x)

    a1 = 75.196
    a3 = 0.12694
    a5 = 1.0345e-5
    a7 = 0.030234
    a9 = 3.5256e-5
    a11 = 0.25645
    a13 = 1.3514e-5
    a15 = -5.2375e-6
    a17 = 7.0e-10
    a19 = -1.6638e-6
    a21 = 0.0005
    a2 = -3.8112
    a4 = -2.0567e-3
    a6 = -6.8306
    a8 = -1.28134e-3
    a10 = -2.266e-7
    a12 = -3.4604e-3
    a14 = -28.106
    a16 = -6.3e-8
    a18 = 3.4054e-4
    a20 = -2.8673

    x1 = x[1]
    x2 = x[2]
    y1 = x1*x2
    y2 = y1*x1
    y3 = x2^2
    y4 = x1^2

    # --- function value ---

    f = a1 + a2*x1 + a3*y4 + a4*y4*x1 + a5*y4^2 +
        a6*x2 + a7*y1 + a8*x1*y1 + a9*y1*y4 + a10*y2*y4 +
        a11*y3 + a12*x2*y3 + a13*y3^2 + a14/(x2+1) +
        a15*y3*y4 + a16*y1*y4*x2 + a17*y1*y3*y4 + a18*x1*y3 +
        a19*y1*y3 + a20*exp(a21*y1)

    # --- constraints ---

    g[1] = 1 - y1/700.0
    g[2] = y4/25.0^2 - x2/5.0
    g[3] = (x1/500.0- 0.11) - (x2/50.0-1)^2

    return f  
end


x0 = [10.0; 10.0]
lx = [0.0; 0.0]
ux = [65.0; 70.0]

ng = 3
options = Options(solver=IPOPT(), derivatives=ForwardFD())
xopt, fopt, info, out = minimize(barnes, x0, ng, lx, ux, -Inf, 0.0, options)


@test isapprox(xopt[1], 49.5263; atol=1e-4)
@test isapprox(xopt[2], 19.6228; atol=1e-4)
@test isapprox(fopt, -31.6368; atol=1e-4)
@test info == :Solve_Succeeded || info == :Solved_To_Acceptable_Level

if snopttest
    options = Options(solver=SNOPT(), derivatives=ForwardAD())
    xopt, fopt, info, out = minimize(barnes, x0, ng, lx, ux, -Inf, 0.0, options)

    @test isapprox(xopt[1], 49.5263; atol=1e-4)
    @test isapprox(xopt[2], 19.6228; atol=1e-4)
    @test isapprox(fopt, -31.6368; atol=1e-4)
    @test info == "Finished successfully: optimality conditions satisfied"

    options = Options(solver=SNOPT(), derivatives=ComplexStep())
    xopt, fopt, info, out = minimize(barnes, x0, ng, lx, ux, -Inf, 0.0, options)

    @test isapprox(xopt[1], 49.5263; atol=1e-4)
    @test isapprox(xopt[2], 19.6228; atol=1e-4)
    @test isapprox(fopt, -31.6368; atol=1e-4)
    @test info == "Finished successfully: optimality conditions satisfied"
end


function sparsegrad(g, x)

    f = x[1]^2 - x[2]

    g[1] = x[2] - 2*x[1]
    g[2] = -x[2]

    return f
end

x0 = [0.0; 0.0]
lx = [-10.0, -10.0]
ux = [10.0, 10.0]
ng = 2

# detect sparsity pattern
sp = SparsePattern(ForwardAD(), sparsegrad, ng, lx, ux)

if snopttest
    options = Options(solver=SNOPT(), derivatives=[ReverseAD(), ForwardAD()], sparsity=sp)
    xopt, fopt, info, out = minimize(sparsegrad, x0, ng, lx, ux, -Inf, 0.0, options)

    @test isapprox(xopt[1], 1.0; atol=1e-6)
    @test isapprox(xopt[2], 2.0; atol=1e-6)
    @test isapprox(fopt, -1.0; atol=1e-5)
    @test info == "Finished successfully: optimality conditions satisfied"
end

end


# @testset "problem format" begin

# function test3!(g, prob, x)
#     return nothing
# end

# prob = SNOW.createproblem(test3!, "test3")

# x = [1.0, 2.0, 3.0]
# lx = [0.0, 0.0, 0.0]
# ux = 10*ones(3)
# names = ["c1", "c2", "c3"]
# SNOW.add_dv!(prob, x, lx, ux, names)

# x2 = [8.0, 2.0]
# lx2 = [0.0, 0.0, 0.0]
# ux2 = 5*ones(3)
# names2 = ["t1", "t2"]
# SNOW.add_dv!(prob, x2, lx2, ux2, names2)

# x = rand(5)
# SNOW.get_dvs(prob, x)

# end
