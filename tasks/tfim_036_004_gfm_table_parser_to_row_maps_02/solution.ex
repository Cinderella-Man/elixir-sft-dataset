  test "parses a basic table with header, separator, and rows" do
    md = """
    | Name | Age |
    | --- | --- |
    | Alice | 30 |
    | Bob | 25 |
    """

    assert parse(md) == [
             %{
               headers: ["Name", "Age"],
               alignments: [:none, :none],
               rows: [
                 %{"Name" => "Alice", "Age" => "30"},
                 %{"Name" => "Bob", "Age" => "25"}
               ]
             }
           ]
  end