module thesisParse

export harvest_theses, download_pdfs, harvest_msc_theses
export process_pdf_with_grobid, parse_tei_xml, batch_process_theses, batch_process_theses_concurrent
export extract_references

include("thesis_harvester.jl")
include("grobid_parser.jl")
include("ReferenceAnalyzer.jl")

using .GrobidParser
using .ReferenceAnalyzer

end # module thesisParse
