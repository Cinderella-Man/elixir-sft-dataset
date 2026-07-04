  test "malformed bullet reports line number and reason" do
    md = """
    ## Misc
    - just a plain bullet
    - **Good**: Proper (tag)
    """

    %{categories: [%{items: items}], errors: errors} = parse(md)
    assert Enum.map(items, & &1.name) == ["Good"]
    assert errors == [%{line: 2, content: "- just a plain bullet", reason: :malformed_item}]
  end