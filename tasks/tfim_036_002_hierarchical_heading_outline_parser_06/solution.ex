  test "closing a branch and opening an ancestor sibling" do
    md = """
    # One
    ## OneA
    # Two
    """

    result = parse(md)
    assert Enum.map(result, & &1.title) == ["One", "Two"]
    [one, two] = result
    assert Enum.map(one.children, & &1.title) == ["OneA"]
    assert two.children == []
  end