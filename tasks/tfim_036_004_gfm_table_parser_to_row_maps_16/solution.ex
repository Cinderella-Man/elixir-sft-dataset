  test "header and separator alone yield a table with zero rows" do
    md = """
    | A | B |
    | --- | :---: |
    """

    assert parse(md) == [%{headers: ["A", "B"], alignments: [:none, :center], rows: []}]
  end