  test "unsupported headings are reported but do not close the open category" do
    md = """
    # Title
    ## Real
    ### Subsection
    - **x**: still under Real (a)
    """

    %{categories: [cat], errors: errors} = parse(md)
    assert cat.category == "Real"
    assert Enum.map(cat.items, & &1.name) == ["x"]

    reasons = Enum.map(errors, &{&1.line, &1.reason})
    assert reasons == [{1, :unsupported_heading}, {3, :unsupported_heading}]
  end