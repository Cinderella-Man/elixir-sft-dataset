  test "parses a single category with one fully-formed item" do
    md = """
    ## Tools

    - **Hammer**: Drives nails (hardware, manual)
    """

    assert parse(md) == [
             %{
               category: "Tools",
               items: [
                 %{name: "Hammer", description: "Drives nails", tags: ["hardware", "manual"]}
               ]
             }
           ]
  end