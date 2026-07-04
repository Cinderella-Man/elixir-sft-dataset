  test "H2 heading with no items has empty items list" do
    md = """
    ## EmptyCategory
    """

    assert parse(md) == [%{category: "EmptyCategory", items: []}]
  end