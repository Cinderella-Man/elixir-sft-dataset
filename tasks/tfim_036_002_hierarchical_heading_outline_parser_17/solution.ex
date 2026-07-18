  test "shallower heading closes deep branch and becomes an ancestor's child sibling" do
    md = """
    # One
    ## Two
    ### Three
    ## Four
    - **f**: under four
    """

    [one] = parse(md)
    assert Enum.map(one.children, & &1.title) == ["Two", "Four"]
    [two, four] = one.children
    assert Enum.map(two.children, & &1.title) == ["Three"]
    assert [%{name: "f", description: "under four", tags: []}] = four.items
    assert four.level == 2
  end