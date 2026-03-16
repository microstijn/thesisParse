using HTTP
using EzXML
using DataFrames
using CSV
using URIs

function harvest_theses(; max_pages::Int=5, output_csv::String="theses_metadata.csv")
    base_url = "https://library.wur.nl/oai"
    verb = "ListRecords"
    metadata_prefix = "oai_dc"

    # Initialize DataFrame
    df = DataFrame(Year=String[], Title=String[], Creator=String[], URL=String[])

    # First request
    url = "$base_url?verb=$verb&metadataPrefix=$metadata_prefix"

    page = 1
    while page <= max_pages
        println("Fetching page $page...")

        response = HTTP.get(url)
        doc = parsexml(String(response.body))
        xml_root = root(doc)

        records = findall("//*[local-name()='record']", xml_root)

        for record in records
            # Find all types
            types = findall(".//*[local-name()='type']", record)
            is_thesis = false
            for t in types
                t_content = lowercase(nodecontent(t))
                if occursin("thesis", t_content) || occursin("dissertation", t_content)
                    is_thesis = true
                    break
                end
            end

            if is_thesis
                titles = findall(".//*[local-name()='title']", record)
                title = isempty(titles) ? "" : join([nodecontent(t) for t in titles], ", ")

                dates = findall(".//*[local-name()='date']", record)
                date = isempty(dates) ? "" : join([nodecontent(d) for d in dates], ", ")

                creators = findall(".//*[local-name()='creator']", record)
                creator = isempty(creators) ? "" : join([nodecontent(c) for c in creators], ", ")

                identifiers = findall(".//*[local-name()='identifier']", record)
                # find first that starts with http
                url_found = ""
                for id in identifiers
                    id_content = nodecontent(id)
                    if startswith(id_content, "http")
                        url_found = id_content
                        break
                    end
                end

                push!(df, (date, title, creator, url_found))
            end
        end

        # Check resumptionToken
        resumption_tokens = findall("//*[local-name()='resumptionToken']", xml_root)
        if isempty(resumption_tokens)
            println("No resumptionToken found. Finished harvesting.")
            break
        end

        token = nodecontent(resumption_tokens[1])
        if isempty(token)
            println("Empty resumptionToken found. Finished harvesting.")
            break
        end

        encoded_token = URIs.escapeuri(token)
        url = "$base_url?verb=$verb&resumptionToken=$encoded_token"
        page += 1
    end

    CSV.write(output_csv, df)
    println("Saved metadata to $output_csv")

    return df
end

function sanitize_filename(title::String)
    # Take first 30 characters safely using first() to avoid multi-byte Unicode slicing errors
    s = length(title) > 30 ? first(title, 30) : title
    # Strip out special characters (keep alphanumeric, space, and simple punctuation)
    s = replace(s, r"[^a-zA-Z0-9\s_\-]" => "")
    # Trim whitespace
    s = strip(s)
    return s
end

function download_pdfs(df::DataFrame, output_dir::String)
    if !isdir(output_dir)
        mkdir(output_dir)
    end

    for row in eachrow(df)
        url = row.URL
        if isempty(url)
            continue
        end

        # Build filename
        safe_title = sanitize_filename(row.Title)
        year_str = isempty(row.Year) ? "UnknownYear" : row.Year
        # Sanitize year string as it might contain full dates like 2023-05-12
        year_str = replace(year_str, r"[^a-zA-Z0-9\s_\-]" => "")

        filename = "$(year_str)_$(safe_title).pdf"
        filepath = joinpath(output_dir, filename)

        println("Checking URL: $url")

        try
            # Check content type
            res = HTTP.head(url, redirect=true, status_exception=false)

            # Need to find Content-Type
            content_type = ""
            for header in res.headers
                if lowercase(header[1]) == "content-type"
                    content_type = lowercase(header[2])
                    break
                end
            end

            if occursin("application/pdf", content_type)
                println("Downloading to $filepath...")
                HTTP.download(url, filepath)
            else
                println("Skipping $url - Content-Type is $content_type (not application/pdf)")
            end
        catch e
            println("Error processing $url: $e")
        end

        # Politeness
        sleep(1.5)
    end
end
