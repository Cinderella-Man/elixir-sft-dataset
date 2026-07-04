  test "document with only non-H2 headings returns empty list" do
    md = """
    # Top level
    ### Too deep
    #### Also too deep
    """

    assert parse(md) == []
  end