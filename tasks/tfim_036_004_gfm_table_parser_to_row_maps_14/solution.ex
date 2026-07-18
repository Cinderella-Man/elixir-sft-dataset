  test "rescans from the next line so a later line can become the header" do
    md = """
    | A | B |
    | C | D |
    | --- | --- |
    | 1 | 2 |
    """

    assert parse(md) == [
             %{
               headers: ["C", "D"],
               alignments: [:none, :none],
               rows: [%{"C" => "1", "D" => "2"}]
             }
           ]
  end