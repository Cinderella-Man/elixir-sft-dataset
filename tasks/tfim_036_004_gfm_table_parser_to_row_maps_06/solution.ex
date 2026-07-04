  test "drops extra cells in rows with too many columns" do
    md = """
    | A | B |
    | --- | --- |
    | 1 | 2 | 3 |
    """

    [%{rows: [row]}] = parse(md)
    assert row == %{"A" => "1", "B" => "2"}
  end