  test "nested (space-indented) bullets and malformed bullets are ignored" do
    md = """
    # H
    - **Parent**: top (a)
      - **Child**: indented ignored (b)
    - just a plain bullet
    """

    [%{items: items}] = parse(md)
    assert length(items) == 1
    assert hd(items).name == "Parent"
  end