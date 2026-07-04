  test "tags are individually trimmed of whitespace" do
    md = """
    ## Misc

    - **Item**: Desc ( alpha ,  beta , gamma )
    """

    [%{items: [item]}] = parse(md)
    assert item.tags == ["alpha", "beta", "gamma"]
  end