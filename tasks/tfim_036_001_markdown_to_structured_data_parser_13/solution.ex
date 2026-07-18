  test "H1 headings are ignored and do not create categories" do
    md = """
    # Document Title

    ## Actual Category

    - **Thing**: A thing (a, b)
    """

    result = parse(md)
    assert length(result) == 1
    assert hd(result).category == "Actual Category"
  end