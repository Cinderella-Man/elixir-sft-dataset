  test "touching intervals overlap" do
    tree = build([{1, 5}, {5, 10}])
    result = T.overlapping(tree, {5, 5})
    assert length(result) == 2
    assert {1, 5} in result
    assert {5, 10} in result
  end