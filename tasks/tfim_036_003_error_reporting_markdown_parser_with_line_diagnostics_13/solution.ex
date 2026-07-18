  test "suppression of a duplicate section ends at the next distinct heading" do
    md = """
    ## A
    - **x**: d
    ## A
    - **suppressed**: gone
    ## B
    - **y**: d2
    """

    %{categories: cats, errors: errors} = parse(md)

    assert cats == [
             %{category: "A", items: [%{name: "x", description: "d", tags: []}]},
             %{category: "B", items: [%{name: "y", description: "d2", tags: []}]}
           ]

    assert errors == [%{line: 3, content: "## A", reason: :duplicate_category}]
  end