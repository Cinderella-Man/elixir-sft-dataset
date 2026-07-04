  test "errors are returned in ascending line order across mixed problems" do
    md = """
    - **early**: orphan (o)
    ## Cat
    - broken bullet
    ### deep
    """

    %{errors: errors} = parse(md)
    assert Enum.map(errors, & &1.line) == [1, 3, 4]

    assert Enum.map(errors, & &1.reason) == [
             :orphan_item,
             :malformed_item,
             :unsupported_heading
           ]
  end