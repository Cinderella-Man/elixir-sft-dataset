  test "enclosing finds interval containing the point" do
    tree = IntervalTree.new() |> IntervalTree.insert({3, 7})
    assert [{3, 7}] = IntervalTree.enclosing(tree, 5)
  end