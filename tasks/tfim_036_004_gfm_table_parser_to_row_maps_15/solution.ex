  test "separator with a different cell count than the header forms no table" do
    md = """
    | A | B |
    | --- |
    | 1 | 2 |
    """

    assert parse(md) == []
  end