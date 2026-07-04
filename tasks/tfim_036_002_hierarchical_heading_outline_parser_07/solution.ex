  test "three levels deep nesting" do
    md = """
    # L1
    ## L2
    ### L3
    - **leaf**: bottom (t)
    """

    [l1] = parse(md)
    [l2] = l1.children
    [l3] = l2.children
    assert {l1.level, l2.level, l3.level} == {1, 2, 3}
    assert [%{name: "leaf", tags: ["t"]}] = l3.items
  end