  test "untagged item gets empty tags list" do
    md = """
    ## H
    - **Widget**: A gadget
    """

    %{categories: [%{items: [item]}]} = parse(md)
    assert item.tags == []
  end