# A little trick for travis
using PkgBenchmark, RewriteTools

pkgpath = dirname(dirname(pathof(RewriteTools)))
# move it out of the repository so that you can check out different branches
script = tempname() * ".jl"
benchpath = joinpath(pkgpath, "benchmark", "benchmarks.jl")
cp(benchpath, script)

j = judge(pkgpath, "main", retune=true, script=script)

println("MASTER BRANCH")
println(j.baseline_results)

println("THIS BRANCH")
println(j.target_results)

println("DIFFGROUP")
println(j.benchmarkgroup)

println("MARKDOWN")
export_markdown(stdout, j, export_invariants=true)
