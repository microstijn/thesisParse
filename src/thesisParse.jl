module thesisParse

export harvest_theses, download_pdfs, harvest_msc_theses
export process_pdf_with_grobid, parse_tei_xml, batch_process_theses, batch_process_theses_concurrent

include("thesis_harvester.jl")
include("grobid_parser.jl")

using .GrobidParser

end # module thesisParse
