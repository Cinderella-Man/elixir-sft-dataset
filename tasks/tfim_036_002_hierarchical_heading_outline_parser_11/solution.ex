  test "headings with seven or more hashes are ignored" do
    md = """
    # Real
    ####### Not a heading
    - **x**: kept
    """

    [node] = parse(md)
    assert node.title == "Real"
    assert Enum.map(node.items, & &1.name) == ["x"]
  end