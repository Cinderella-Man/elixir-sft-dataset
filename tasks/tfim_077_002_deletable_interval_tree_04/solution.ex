  test "overlapping returns only matching intervals" do
    tree = build([{1, 2}, {5, 8}, {10, 15}, {20, 25}])
    result = T.overlapping(tree, {6, 12})
    assert length(result) == 2
    assert {5, 8} in result
    assert {10, 15} in result
  end