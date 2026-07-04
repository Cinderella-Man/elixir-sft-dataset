  test "parses multiple tables in document order" do
    md = """
    | X |
    | --- |
    | 1 |

    | Y |
    | --- |
    | 2 |
    """

    result = parse(md)
    assert length(result) == 2
    assert Enum.map(result, & &1.headers) == [["X"], ["Y"]]
  end