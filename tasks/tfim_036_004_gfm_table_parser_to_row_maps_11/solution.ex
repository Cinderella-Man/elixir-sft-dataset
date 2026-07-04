  test "a header without a valid separator is not a table" do
    md = """
    | A | B |
    | 1 | 2 |
    """

    assert parse(md) == []
  end