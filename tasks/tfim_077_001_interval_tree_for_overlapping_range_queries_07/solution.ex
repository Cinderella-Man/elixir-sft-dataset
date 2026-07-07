  test "enclosing misses interval that does not contain the point" do
    tree = IntervalTree.new() |> IntervalTree.insert({3, 7})
    assert [] = IntervalTree.enclosing(tree, 8)
  end