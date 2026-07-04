  test "derives alignments from separator markers" do
    md = """
    | L | C | R |
    | :--- | :---: | ---: |
    | 1 | 2 | 3 |
    """

    [table] = parse(md)
    assert table.alignments == [:left, :center, :right]
  end