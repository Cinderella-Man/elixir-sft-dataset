  test "item with no parentheses gets empty tags list" do
    md = """
    ## Things

    - **Widget**: A small gadget
    """

    [%{items: [item]}] = parse(md)
    assert item.name == "Widget"
    assert item.description == "A small gadget"
    assert item.tags == []
  end