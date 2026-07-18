  test "escaped pipes in a header cell keep one column and key the rows" do
    md = """
    | a \\| b | c |
    | --- | --- |
    | 1 | 2 |
    """

    [table] = parse(md)
    assert table.headers == ["a | b", "c"]
    assert table.rows == [%{"a | b" => "1", "c" => "2"}]
  end