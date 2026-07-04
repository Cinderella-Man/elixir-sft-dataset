  test "same-level headings become siblings" do
    md = """
    # A
    # B
    """

    result = parse(md)
    assert length(result) == 2
    assert Enum.map(result, & &1.title) == ["A", "B"]
    assert Enum.all?(result, &(&1.children == []))
  end