  test "trims whitespace inside cells" do
    md = """
    |   Key   |   Value   |
    | --- | --- |
    |   x   |   y   |
    """

    [table] = parse(md)
    assert table.headers == ["Key", "Value"]
    assert table.rows == [%{"Key" => "x", "Value" => "y"}]
  end