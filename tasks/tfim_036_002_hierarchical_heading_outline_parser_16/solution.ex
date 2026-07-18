  test "empty heading between populated siblings has empty items and children" do
    md = """
    # A
    - **a**: da
    # Empty
    # B
    - **b**: db
    """

    assert [_a, empty, _b] = parse(md)
    assert empty == %{title: "Empty", level: 1, items: [], children: []}
  end