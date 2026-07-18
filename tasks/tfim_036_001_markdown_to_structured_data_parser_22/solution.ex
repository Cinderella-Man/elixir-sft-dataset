  test "a single tag in parentheses yields a one-element tags list" do
    md = """
    ## Single

    - **Solo**: Only one tag (only)
    """

    [%{items: [item]}] = parse(md)
    assert item.description == "Only one tag"
    assert item.tags == ["only"]
  end