  test "multiple categories and their items keep document order" do
    md = """
    ## First
    - **a1**: one
    - **a2**: two (t)
    ## Second
    - **b1**: three
    """

    %{categories: cats, errors: errors} = parse(md)

    assert Enum.map(cats, & &1.category) == ["First", "Second"]
    assert Enum.map(hd(cats).items, & &1.name) == ["a1", "a2"]
    assert Enum.map(List.last(cats).items, & &1.name) == ["b1"]
    assert errors == []
  end