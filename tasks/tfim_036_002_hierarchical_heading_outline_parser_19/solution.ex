  test "hash line without whitespace before the text is not a heading" do
    md = """
    # Real
    #NotAHeading
    - **x**: kept
    """

    [node] = parse(md)
    assert node.title == "Real"
    assert node.children == []
    assert Enum.map(node.items, & &1.name) == ["x"]
  end