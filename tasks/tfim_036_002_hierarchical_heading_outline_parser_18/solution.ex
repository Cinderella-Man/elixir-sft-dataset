  test "six-hash heading is recognised as a level six node" do
    md = """
    # L1
    ###### L6
    - **x**: deep
    """

    [l1] = parse(md)
    assert [%{title: "L6", level: 6, items: [%{name: "x"}], children: []}] = l1.children
  end