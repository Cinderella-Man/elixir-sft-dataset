  test "correct results with many intervals inserted" do
    # Insert 200 non-overlapping intervals: {0,9}, {10,19}, ..., {1990,1999}
    tree =
      Enum.reduce(0..199, IntervalTree.new(), fn i, acc ->
        IntervalTree.insert(acc, {i * 10, i * 10 + 9})
      end)

    # Query that touches exactly three intervals
    result = IntervalTree.overlapping(tree, {95, 115})
    assert length(result) == 3
    assert {90, 99} in result
    assert {100, 109} in result
    assert {110, 119} in result

    # Point query
    result2 = IntervalTree.enclosing(tree, 155)
    assert [{150, 159}] = result2
  end