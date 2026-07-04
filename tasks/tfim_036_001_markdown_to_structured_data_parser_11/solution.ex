  test "multiple empty categories" do
    md = """
    ## First

    ## Second

    ## Third
    """

    result = parse(md)
    assert length(result) == 3
    assert Enum.all?(result, fn %{items: items} -> items == [] end)
    assert Enum.map(result, & &1.category) == ["First", "Second", "Third"]
  end