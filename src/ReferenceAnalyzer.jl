module ReferenceAnalyzer

using JSON3
using DataFrames
using CSV

export extract_references

"""
    extract_references(jsonl_path::String; csv_path::Union{String, Nothing}=nothing)

Extracts references from a JSONL file containing parsed theses and returns a flat, tabular DataFrame.

# Arguments
- `jsonl_path::String`: Path to the input JSONL file.
- `csv_path::Union{String, Nothing}`: Optional path to save the resulting DataFrame as a CSV file.

# Details
- Initializes an empty collection to store rows.
- Reads `jsonl_path` line by line using `JSON3.read(line)`.
- Extracts `Thesis_Year` from the first 4 characters of the filename (parses as integer). Skips the file on failure.
- Loops through the `references` array for each thesis.
- Extracts `title`, `authors`, `journal`, `year` (mapped to `Ref_Date`), and `doi`. Converts `nothing` values to `missing`.
- Logs warnings and writes them to `warninglog.txt` for skipped files or missing/malformed records.
- Constructs and returns a DataFrame.
"""
function extract_references(jsonl_path::String; csv_path::Union{String, Nothing}=nothing)
    # Define the row type for performant collection
    # Note: Thesis_Year is Int, Thesis_File is String, reference fields are Union{String, Missing}
    RowType = NamedTuple{
        (:Thesis_Year, :Thesis_File, :Ref_Title, :Ref_Authors, :Ref_Journal, :Ref_Date, :Ref_DOI),
        Tuple{Int, String, Union{String, Missing}, Union{String, Missing}, Union{String, Missing}, Union{String, Missing}, Union{String, Missing}}
    }

    rows = RowType[]

    # Open warning log file
    open("warninglog.txt", "w") do logfile
        open(jsonl_path, "r") do f
            for (line_idx, line) in enumerate(eachline(f))
                # Skip completely empty lines
                if isempty(strip(line))
                    continue
                end

                # Parse JSON
                local parsed
                try
                    parsed = JSON3.read(line)
                catch e
                    msg = "Line $(line_idx): Failed to parse JSON. Skipping.\n"
                    @warn msg
                    write(logfile, msg)
                    continue
                end

                # Extract filename
                filename = get(parsed, :filename, nothing)
                if filename === nothing
                    msg = "Line $(line_idx): Missing or null 'filename' key. Skipping.\n"
                    @warn msg
                    write(logfile, msg)
                    continue
                end

                # Ensure filename is a string representation to slice safely
                filename_str = string(filename)

                # Extract thesis year from the first 4 characters of filename
                local thesis_year
                if length(filename_str) < 4
                    msg = "Line $(line_idx): Filename '$(filename_str)' is too short to extract year. Skipping.\n"
                    @warn msg
                    write(logfile, msg)
                    continue
                end

                try
                    thesis_year = parse(Int, first(filename_str, 4))
                catch e
                    msg = "Line $(line_idx): Failed to parse Thesis_Year from filename '$(filename_str)'. Skipping.\n"
                    @warn msg
                    write(logfile, msg)
                    continue
                end

                # Extract references
                refs = get(parsed, :references, nothing)
                if refs === nothing || isempty(refs)
                    msg = "Line $(line_idx): No references found for thesis '$(filename_str)'. Skipping.\n"
                    @warn msg
                    write(logfile, msg)
                    continue
                end

                for ref in refs
                    # Extract reference fields, converting nothing to missing
                    ref_title = get(ref, :title, nothing)
                    ref_title = (ref_title === nothing) ? missing : string(ref_title)

                    ref_authors = get(ref, :authors, nothing)
                    ref_authors = (ref_authors === nothing) ? missing : string(ref_authors)

                    ref_journal = get(ref, :journal, nothing)
                    ref_journal = (ref_journal === nothing) ? missing : string(ref_journal)

                    ref_date = get(ref, :year, nothing)
                    ref_date = (ref_date === nothing) ? missing : string(ref_date)

                    ref_doi = get(ref, :doi, nothing)
                    ref_doi = (ref_doi === nothing) ? missing : string(ref_doi)

                    # Push the flattened data row
                    push!(rows, (
                        Thesis_Year = thesis_year,
                        Thesis_File = filename_str,
                        Ref_Title = ref_title,
                        Ref_Authors = ref_authors,
                        Ref_Journal = ref_journal,
                        Ref_Date = ref_date,
                        Ref_DOI = ref_doi
                    ))
                end
            end
        end
    end

    # Construct DataFrame from the collected rows
    # This is a performant approach to creating a DataFrame instead of pushing rows one by one.
    df = DataFrame(rows)

    # Save to CSV if requested
    if csv_path !== nothing
        CSV.write(csv_path, df)
    end

    return df
end

end # module ReferenceAnalyzer
