  test "bullets following ignored H3 and H1 headings stay in the preceding H2 category" do
    md = """
    ## Real

    - **First**: Before the H3 (a)

    ### Not a category

    - **Second**: After the H3 (b)

    # Also not a category

    - **Third**: After the H1 (c)
    """

    assert [%{category: "Real", items: items}] = parse(md)
    assert Enum.map(items, & &1.name) == ["First", "Second", "Third"]
    assert Enum.map(items, & &1.tags) == [["a"], ["b"], ["c"]]
  end