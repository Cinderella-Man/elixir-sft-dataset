  test "category whose only bullets are malformed still appears with empty items" do
    md = """
    ## Empty By Malformation

    - plain bullet with no bold name
      - **Nested**: indented child (x)
    - another bad bullet (fake, tags)

    ## Next

    - **Real**: Kept (t)
    """

    result = parse(md)
    assert Enum.map(result, & &1.category) == ["Empty By Malformation", "Next"]
    assert Enum.at(result, 0).items == []
    assert Enum.at(result, 1).items == [%{name: "Real", description: "Kept", tags: ["t"]}]
  end