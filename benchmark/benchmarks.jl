using BenchmarkTools
using SNOW
using SparseArrays

const BENCH_NSAMPLES = parse(Int, get(ENV, "BENCH_NSAMPLES", "2000"))
const BENCH_NEVALS = parse(Int, get(ENV, "BENCH_NEVALS", "1"))
const BENCH_MODE = Symbol(lowercase(get(ENV, "BENCH_MODE", "both")))
const BENCH_ALGORITHMS = let
    names = split(get(ENV, "BENCH_ALGORITHMS", "greedy,greedy_smallest_last,greedy_largest_first,constant"), ',')
    [Symbol(lowercase(name)) for name in names if !isempty(name)]
end

function test2!(g, x)
    nx = length(x)
    @inbounds for i in 1:nx
        im1 = i == 1 ? 0.0 : x[i-1]
        ip1 = i == nx ? 0.0 : x[i+1]
        g[i] = x[i]^2 + 0.1 * im1 + 0.2 * ip1
    end
    return x[1]^2 - x[2]
end

function make_pattern(nx)
    rows = Int[]
    cols = Int[]
    for i in 1:nx
        push!(rows, i)
        push!(cols, i)
        if i > 1
            push!(rows, i)
            push!(cols, i - 1)
        end
        if i < nx
            push!(rows, i)
            push!(cols, i + 1)
        end
    end
    return SNOW.SparsePattern(sparse(rows, cols, ones(Float64, length(rows)), nx, nx))
end

function coloring_algorithm(name::Symbol, nx)
    smc = SNOW.SparseMatrixColorings
    if name == :greedy
        return smc.GreedyColoringAlgorithm()
    elseif name == :greedy_smallest_last
        return smc.GreedyColoringAlgorithm(smc.SmallestLast())
    elseif name == :greedy_largest_first
        return smc.GreedyColoringAlgorithm(smc.LargestFirst())
    elseif name == :constant
        return smc.ConstantColoringAlgorithm(ones(nx, nx), [mod1(i, 3) for i in 1:nx])
    else
        error("invalid benchmark coloring algorithm: $name")
    end
end

function make_benchmark(dmode::Symbol, algorithm::Symbol)
    nx = 300
    ng = nx
    x = 2.0 .* ones(nx)
    g = zeros(ng)
    df = zeros(nx)
    sp = make_pattern(nx)
    dg = zeros(length(sp.rows))
    method = if algorithm == :legacy
        dmode == :fd ? [SNOW.ReverseAD(), SNOW.ForwardFD()] : [SNOW.ReverseAD(), SNOW.ForwardAD()]
    else
        alg = coloring_algorithm(algorithm, nx)
        dmode == :fd ? [SNOW.ReverseAD(), SNOW.ForwardFD(coloring_algorithm=alg)] :
            [SNOW.ReverseAD(), SNOW.ForwardAD(coloring_algorithm=alg)]
    end

    cache = SNOW.createcache(sp, method, test2!, nx, ng)

    SNOW.evaluate!(g, df, dg, x, cache)
    return @benchmarkable SNOW.evaluate!($g, $df, $dg, $x, $cache) samples=BENCH_NSAMPLES evals=BENCH_NEVALS
end

if BENCH_MODE ∉ (:ad, :fd, :both)
    error("invalid BENCH_MODE=$(BENCH_MODE); expected ad, fd, or both")
end

const BENCH_MODES = BENCH_MODE == :both ? (:ad, :fd) : (BENCH_MODE,)
const SUITE = BenchmarkGroup()
for mode in BENCH_MODES
    group = SUITE[String(mode)] = BenchmarkGroup()
    for algorithm in BENCH_ALGORITHMS
        group[String(algorithm)] = make_benchmark(mode, algorithm)
    end
end
