# activate the project environment
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

# import packages
using thesisParse

# harvest metadata and save to CSV

fold = raw"C:\Users\peete074\Downloads\temp_try"

outfile = joinpath(fold, "theses_metadata.csv")

harvest_theses(
    max_pages  = 10,
    output_csv = outfile
)
