  test "tags are trimmed and empty tags dropped" do
    md = """
    ## H
    - **i**: d ( a , b ,, c )
    """

    %{categories: [%{items: [item]}]} = parse(md)
    assert item.tags == ["a", "b", "c"]
  end