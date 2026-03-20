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


# =========================================================
# GROBID PARSER TEST
# =========================================================
# activate the project environment
# docker run --rm --init --ulimit core=0 -p 8070:8070 grobid/grobid:0.8.2-full
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using thesisParse
fold = raw"C:\Users\peete074\Downloads\temp_try"
pdf_out_dir = joinpath(fold, "pdfs")

# Define your final output destinations
final_jsonl = joinpath(fold, "msc_theses_parsed.jsonl")
final_xml_dir = joinpath(fold, "msc_xml_archive")

# Get all downloaded PDFs
all_pdfs = filter(f -> endswith(lowercase(f), ".pdf"), readdir(pdf_out_dir, join=true))
println("Found $(length(all_pdfs)) PDFs to process.")

if length(all_pdfs) > 0
    println("Igniting concurrent GROBID workers. This may take a few hours...")
    println("Monitoring memory to keep Docker stable...")
    
    # Run the concurrent processor! 
    # max_concurrent=2 is safe. If you have 16GB+ of RAM, you can try 3.
    batch_process_theses_concurrent(
        pdf_out_dir, 
        final_jsonl, 
        final_xml_dir; 
        max_concurrent  = 2, 
        min_free_mem_gb = 1.0
    )
    
    println("\nProcessing Complete! All data saved to $final_jsonl")
end