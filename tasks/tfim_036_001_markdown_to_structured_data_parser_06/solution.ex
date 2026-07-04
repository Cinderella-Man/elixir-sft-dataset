  test "mix of tagged and untagged items in same category" do
    md = """
    ## Mix

    - **A**: Has tags (x, y)
    - **B**: No tags
    """

    [%{items: [a, b]}] = parse(md)
    assert a.tags == ["x", "y"]
    assert b.tags == []
  end