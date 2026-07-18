  test "nested bullet lines (indented with spaces) are ignored" do
    md = """
    ## Nested

    - **Parent**: Top level item (a)
      - **Child**: Should be ignored (b)
    """

    [%{items: items}] = parse(md)
    assert length(items) == 1
    assert hd(items).name == "Parent"
  end