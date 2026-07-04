  test "orphan item before any heading is reported and discarded" do
    md = """
    - **Orphan**: lost (x)
    ## Real
    - **Kept**: yes
    """

    %{categories: [cat], errors: errors} = parse(md)
    assert cat.category == "Real"
    assert Enum.map(cat.items, & &1.name) == ["Kept"]
    assert errors == [%{line: 1, content: "- **Orphan**: lost (x)", reason: :orphan_item}]
  end