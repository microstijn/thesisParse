# activate the project environment
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

# import packages
using thesisParse

# harvest metadata and save to CSV

fold = raw"C:\Users\peete074\Downloads\temp_try"

# set up your variables
start_year = 1992
end_year = 2026
fold = raw"C:\Users\peete074\Downloads\temp_try"
outfile = joinpath(fold, "msc_theses_metadata.csv")

# harvest the MSc theses
println("Harvesting MSc theses from $start_year to $end_year...")
df_msc = harvest_msc_theses(start_year, end_year)

# save the resulting DataFrame to a CSV
using CSV
CSV.write(outfile, df_msc)

using DataFrames
dat = CSV.File(outfile) |> DataFrame 

pdf_out_dir = joinpath(fold, "pdfs")

download_pdfs(dat, pdf_out_dir)

