  test "duplicate category is reported and its section suppressed silently" do
    md = """
    ## A
    - **x**: d
    ## A
    - **y**: d2
    """

    %{categories: cats, errors: errors} = parse(md)
    assert cats == [%{category: "A", items: [%{name: "x", description: "d", tags: []}]}]
    assert errors == [%{line: 3, content: "## A", reason: :duplicate_category}]
  end