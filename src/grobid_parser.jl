module GrobidParser

using HTTP
using EzXML
using JSON3
using URIs

export process_pdf_with_grobid, parse_tei_xml, batch_process_theses, batch_process_theses_concurrent

"""
    process_pdf_with_grobid(filepath::String; host="http://localhost:8070")

Sends a PDF file to a local GROBID server and returns the raw TEI-XML string.
"""
function process_pdf_with_grobid(filepath::String; host="http://localhost:8070")
    if !isfile(filepath)
        error("File not found: $filepath")
    end

    url = "$host/api/processFulltextDocument"

    # We open the file and read it, then send it as a multipart/form-data
    try
        open(filepath, "r") do f
            body = HTTP.Form(Dict("input" => f))
            response = HTTP.post(url, body=body)
            if response.status == 200
                return String(response.body)
            else
                @warn "GROBID returned status $(response.status) for file $filepath"
                return nothing
            end
        end
    catch e
        @warn "HTTP request failed for file $filepath: $e"
        return nothing
    end
end

"""
    parse_tei_xml(xml_string::String)

Parses a TEI-XML string from GROBID, extracting the body text and references.
"""
function parse_tei_xml(xml_string::String)
    # Strip the XML namespace to make xpath queries simpler
    clean_xml = replace(xml_string, r"xmlns=\"[^\"]+\"" => "")

    doc = EzXML.parsexml(clean_xml)

    # Extract Body Text
    paragraphs = findall("//text//body//p", doc)
    body_text_parts = String[]
    for p in paragraphs
        text_content = EzXML.nodecontent(p)
        # Clean up excess whitespace
        clean_text = replace(text_content, r"\s+" => " ")
        clean_text = strip(clean_text)
        if !isempty(clean_text)
            push!(body_text_parts, clean_text)
        end
    end
    body_text = join(body_text_parts, "\n")

    # Extract References
    bib_structs = findall("//listBibl//biblStruct", doc)
    references = Dict{String, Union{String, Nothing}}[]

    for bib in bib_structs
        title_node = findfirst(".//title[@level='a']", bib)
        if isnothing(title_node)
            title_node = findfirst(".//title[@level='m']", bib)
        end
        if isnothing(title_node)
            title_node = findfirst(".//title", bib)
        end

        title = isnothing(title_node) ? nothing : strip(EzXML.nodecontent(title_node))

        date_node = findfirst(".//date", bib)
        year = nothing
        if !isnothing(date_node)
            if haskey(date_node, "when")
                year = date_node["when"]
            else
                year = strip(EzXML.nodecontent(date_node))
            end
        end

        doi_node = findfirst(".//idno[@type='DOI']", bib)
        doi = isnothing(doi_node) ? nothing : strip(EzXML.nodecontent(doi_node))

        author_nodes = findall(".//author//persName", bib)
        if isempty(author_nodes)
            authors = nothing
        else
            author_names = String[]
            for node in author_nodes
                # Clean up excess whitespace
                clean_name = strip(replace(EzXML.nodecontent(node), r"\s+" => " "))
                if !isempty(clean_name)
                    push!(author_names, clean_name)
                end
            end
            authors = isempty(author_names) ? nothing : join(author_names, "; ")
        end

        journal_node = findfirst(".//title[@level='j']", bib)
        journal = isnothing(journal_node) ? nothing : strip(replace(EzXML.nodecontent(journal_node), r"\s+" => " "))

        push!(references, Dict(
            "title" => title,
            "year" => year,
            "doi" => doi,
            "authors" => authors,
            "journal" => journal
        ))
    end

    return Dict(
        "body_text" => body_text,
        "references" => references
    )
end

"""
    batch_process_theses(pdf_dir::String, output_jsonl::String; error_log="error_log.txt")

Processes all PDFs in a directory with GROBID and saves the parsed data as JSONLines.
Logs errors for files that failed to process into `error_log`.
"""
function batch_process_theses(pdf_dir::String, output_jsonl::String; error_log::String="error_log.txt")
    if !isdir(pdf_dir)
        error("Directory not found: $pdf_dir")
    end

    pdf_files = filter(f -> endswith(lowercase(f), ".pdf"), readdir(pdf_dir, join=true))

    open(output_jsonl, "a") do io
        open(error_log, "a") do err_io
            for filepath in pdf_files
                try
                    xml_string = process_pdf_with_grobid(filepath)
                    if isnothing(xml_string)
                        msg = "Skipping file due to GROBID processing failure: $filepath\n"
                        @warn msg
                        print(err_io, msg)
                        flush(err_io)
                        continue
                    end

                    parsed_data = parse_tei_xml(xml_string)

                    # Add filename to the dictionary
                    parsed_data["filename"] = basename(filepath)

                    # Write to JSONLines
                    JSON3.write(io, parsed_data)
                    println(io) # Add newline for JSONL format
                    flush(io) # Save progress incrementally

                catch e
                    msg = "Failed to process and parse file: $filepath. Error: $e\n"
                    @warn msg
                    print(err_io, msg)
                    flush(err_io)
                end
            end
        end
    end
end


"""
    batch_process_theses_concurrent(pdf_dir::String, output_jsonl::String, xml_dir::String; error_log::String="error_log.txt", max_concurrent::Int=3, min_free_mem_gb::Float64=2.0)

Processes all PDFs in a directory concurrently with GROBID, saves the raw XML, and saves the parsed data as JSONLines.
Uses a memory throttle to wait if free memory drops below `min_free_mem_gb`.
"""
function batch_process_theses_concurrent(pdf_dir::String, output_jsonl::String, xml_dir::String; error_log::String="error_log.txt", max_concurrent::Int=3, min_free_mem_gb::Float64=2.0)
    if !isdir(pdf_dir)
        error("Directory not found: $pdf_dir")
    end

    mkpath(xml_dir)

    pdf_files = filter(f -> endswith(lowercase(f), ".pdf"), readdir(pdf_dir, join=true))

    my_io_lock = ReentrantLock()

    open(output_jsonl, "a") do io
        open(error_log, "a") do err_io
            asyncmap(pdf_files; ntasks=max_concurrent) do filepath
                try
                    # Memory Throttle
                    while Sys.free_memory() / (1024^3) < min_free_mem_gb
                        free_mem_gb = round(Sys.free_memory() / (1024^3), digits=2)
                        println("Memory low ($free_mem_gb GB free). Worker pausing...")
                        sleep(2.0)
                    end

                    xml_string = process_pdf_with_grobid(filepath)
                    if isnothing(xml_string)
                        msg = "Skipping file due to GROBID processing failure: $filepath\n"
                        @warn msg
                        lock(my_io_lock) do
                            print(err_io, msg)
                            flush(err_io)
                        end
                        return
                    end

                    # Save raw XML
                    base_name = splitext(basename(filepath))[1]
                    xml_filepath = joinpath(xml_dir, base_name * ".xml")
                    write(xml_filepath, xml_string)

                    parsed_data = parse_tei_xml(xml_string)

                    # Add filename to the dictionary
                    parsed_data["filename"] = basename(filepath)

                    # Write to JSONLines safely
                    lock(my_io_lock) do
                        JSON3.write(io, parsed_data)
                        println(io) # Add newline for JSONL format
                        flush(io) # Save progress incrementally
                    end

                catch e
                    msg = "Failed to process and parse file: $filepath. Error: $e\n"
                    @warn msg
                    lock(my_io_lock) do
                        print(err_io, msg)
                        flush(err_io)
                    end
                end
            end
        end
    end
end

end # module GrobidParser