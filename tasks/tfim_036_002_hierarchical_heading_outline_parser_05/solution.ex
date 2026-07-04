  test "relative nesting: H1 then H3 makes H3 a child of H1" do
    md = """
    # Top
    ### Deep
    - **d**: under deep
    """

    [top] = parse(md)
    assert top.title == "Top"
    assert top.level == 1
    assert [deep] = top.children
    assert deep.title == "Deep"
    assert deep.level == 3
    assert [%{name: "d"}] = deep.items
  end