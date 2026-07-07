  test "enclosing returns all intervals covering the point" do
    tree = build([{1, 10}, {3, 7}, {6, 15}, {20, 30}])
    result = T.enclosing(tree, 6)
    assert length(result) == 3
    refute {20, 30} in result
  end