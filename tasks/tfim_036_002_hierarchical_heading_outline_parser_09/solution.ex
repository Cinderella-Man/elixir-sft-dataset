  test "tags are individually trimmed and empty tags dropped" do
    md = """
    # H
    - **i**: d ( a , b ,, c )
    """

    [%{items: [item]}] = parse(md)
    assert item.tags == ["a", "b", "c"]
  end