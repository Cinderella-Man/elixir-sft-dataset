  test "multiple items and multiple children keep document order" do
    md = """
    # Root
    - **i1**: one
    - **i2**: two
    - **i3**: three
    ## C1
    ## C2
    ## C3
    """

    [root] = parse(md)
    assert Enum.map(root.items, & &1.name) == ["i1", "i2", "i3"]
    assert Enum.map(root.children, & &1.title) == ["C1", "C2", "C3"]
  end