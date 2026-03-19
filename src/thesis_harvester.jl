using HTTP
using EzXML
using DataFrames
using CSV
using URIs
using Gumbo
using Cascadia
using ProgressMeter

function harvest_msc_theses(start_year::Int, end_year::Int)
    df = DataFrame(Year=String[], Title=String[], Creator=String[], URL=String[])
    base_url = "https://library.wur.nl/WebQuery/theses"

    for year in start_year:end_year
        offset = 0
        while true
            println("Fetching year $year, offset $offset...")

            # The query parameters required for pagination and year filtering
            url = "$base_url?q=*&wq_flt=jaar&wq_val=$year&wq_max=100&wq_ofs=$offset"

            response = HTTP.get(url, status_exception=false)
            if response.status != 200
                println("Failed to fetch $url. Status code: $(response.status)")
                break
            end

            body = String(response.body)
            html = Gumbo.parsehtml(body)

            records = eachmatch(Selector(".record_summary"), html.root)

            if isempty(records)
                break
            end

            for r in records
                # Extract title and URL
                title_el = eachmatch(Selector("a.title"), r)
                title = isempty(title_el) ? "" : strip(text(title_el[1]))

                href = ""
                if !isempty(title_el)
                    href = getattr(title_el[1], "href", "")
                    if startswith(href, "/")
                        href = "https://library.wur.nl" * href
                    elseif !startswith(href, "http") && !isempty(href)
                        href = "https://library.wur.nl/" * href
                    end
                end

                # Extract creator
                author_el = eachmatch(Selector(".author span"), r)
                creator = isempty(author_el) ? "" : strip(text(author_el[1]))

                push!(df, (string(year), title, creator, href))
            end

            offset += 100
            sleep(1.0)
        end
    end

    return df
end

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
    # Create the directory if it doesn't exist
    if !isdir(output_dir)
        mkdir(output_dir)
    end

    total_files = nrow(df)
    error_log_path = joinpath(output_dir, "missed_urls.txt")
    
    # The @showprogress macro automatically handles the progress bar
    @showprogress 1 "Downloading $total_files PDFs..." for row in eachrow(df)
        url = row.URL
        if ismissing(url) || isempty(url)
            continue
        end

        # --- FIX 1: Safe Year and Title String Parsing ---
        year_raw = ismissing(row.Year) ? "" : string(row.Year)
        year_str = isempty(year_raw) ? "UnknownYear" : year_raw
        year_str = replace(year_str, r"[^a-zA-Z0-9\s_\-]" => "")

        title_raw = ismissing(row.Title) ? "UnknownTitle" : string(row.Title)
        safe_title = sanitize_filename(title_raw)
        
        filename = "$(year_str)_$(safe_title).pdf"
        filepath = joinpath(output_dir, filename)

        is_pdf = false
        content_type = ""
        
        # 1st Attempt: Check if the direct URL is already a PDF or an eDepot link
        try
            res = HTTP.head(url, redirect=true, status_exception=false)

            for header in res.headers
                if lowercase(header[1]) == "content-type"
                    content_type = lowercase(header[2])
                    break
                end
            end

            # --- THE MAGIC FIX: Trust eDepot links automatically ---
            if occursin("application/pdf", content_type) || occursin("edepot.wur.nl", lowercase(url))
                is_pdf = true
                HTTP.download(url, filepath)
            end
        catch e
            # Silenced to protect progress bar
        end

        # 2nd Attempt: If direct link wasn't a PDF, scan the HTML page
        if !is_pdf
            try
                res_get = HTTP.get(url, redirect=true, status_exception=false)
                html_string = String(res_get.body)

                # --- FIX 2: Updated Regex to catch WUR eDepot links ---
                m = match(r"href=\"([^\"]+\.pdf|https?://edepot\.wur\.nl/\d+)\"i", html_string)
                
                if m !== nothing
                    pdf_url = String(m.captures[1])
                    
                    # Fix relative URLs
                    if startswith(pdf_url, "http")
                        # Leave it as is
                    elseif startswith(pdf_url, "/")
                        pdf_url = "https://research.wur.nl" * pdf_url
                    else
                        pdf_url = "https://research.wur.nl/" * pdf_url
                    end

                    # Verify the found link
                    res_head = HTTP.head(pdf_url, redirect=true, status_exception=false)
                    pdf_content_type = ""
                    for header in res_head.headers
                        if lowercase(header[1]) == "content-type"
                            pdf_content_type = lowercase(header[2])
                            break
                        end
                    end

                    # Download if it's a PDF OR if it's an eDepot link (which sometimes hide their headers)
                    if occursin("application/pdf", pdf_content_type) || occursin("edepot", pdf_url)
                        HTTP.download(pdf_url, filepath)
                    else
                        # --- FIX 3: Error Logging ---
                        open(error_log_path, "a") do file
                            write(file, "Found link but not a PDF ($pdf_content_type): $url -> $pdf_url\n")
                        end
                    end
                else
                    # --- FIX 3: Error Logging ---
                    open(error_log_path, "a") do file
                        write(file, "No PDF or eDepot link found on page: $url\n")
                    end
                end
            catch e
                 open(error_log_path, "a") do file
                    write(file, "Error fetching HTML for $url: $e\n")
                end
            end
        end

        # Politeness constraint to prevent server blocks
        sleep(1.0)
    end
end
