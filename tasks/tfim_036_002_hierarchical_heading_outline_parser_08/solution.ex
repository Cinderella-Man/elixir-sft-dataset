  test "items before the first heading are discarded" do
    md = """
    - **orphan**: lost (x)
    # Real
    - **kept**: yes
    """

    [node] = parse(md)
    assert node.title == "Real"
    assert Enum.map(node.items, & &1.name) == ["kept"]
  end