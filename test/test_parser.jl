using Test
using JSON3
include("../src/grobid_parser.jl")
using .GrobidParser

@testset "TEI-XML Parsing" begin
    # Minimal valid GROBID TEI-XML structure
    mock_tei_xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <TEI xmlns="http://www.tei-c.org/ns/1.0">
        <teiHeader>
        </teiHeader>
        <text>
            <body>
                <p>This is the first paragraph.</p>
                <p>  This is the second    paragraph with extra whitespace.  </p>
            </body>
            <back>
                <div type="references">
                    <listBibl>
                        <biblStruct>
                            <analytic>
                                <title level="a" type="main">Test Title 1</title>
                        <author>
                            <persName>
                                <forename>John</forename>
                                <surname>Doe</surname>
                            </persName>
                        </author>
                        <author>
                            <persName>Jane  Smith</persName>
                        </author>
                            </analytic>
                            <monogr>
                        <title level="j">Journal of Testing</title>
                                <imprint>
                                    <date type="published" when="2020-05-10" />
                                </imprint>
                            </monogr>
                            <idno type="DOI">10.1234/test.doi.1</idno>
                        </biblStruct>
                        <biblStruct>
                            <monogr>
                                <title level="m">Test Book Title 2</title>
                                <imprint>
                                    <date>2021</date>
                                </imprint>
                            </monogr>
                        </biblStruct>
                    </listBibl>
                </div>
            </back>
        </text>
    </TEI>
    """

    parsed = parse_tei_xml(mock_tei_xml)

    @testset "Body Text Parsing" begin
        # Body text should match concatenated paragraphs, cleaned of extra whitespace
        expected_body = "This is the first paragraph.\nThis is the second paragraph with extra whitespace."
        @test parsed["body_text"] == expected_body
    end

    @testset "References Parsing" begin
        refs = parsed["references"]

        # Should extract exactly 2 references
        @test length(refs) == 2

        # First reference (with a-level title, when attribute, DOI, authors, and journal)
        @test refs[1]["title"] == "Test Title 1"
        @test refs[1]["year"] == "2020-05-10"
        @test refs[1]["doi"] == "10.1234/test.doi.1"
        @test refs[1]["authors"] == "John Doe; Jane Smith"
        @test refs[1]["journal"] == "Journal of Testing"

        # Second reference (with m-level title, node text date, and NO DOI, NO authors, NO journal)
        @test refs[2]["title"] == "Test Book Title 2"
        @test refs[2]["year"] == "2021"
        @test refs[2]["doi"] === nothing
        @test refs[2]["authors"] === nothing
        @test refs[2]["journal"] === nothing
    end
end
