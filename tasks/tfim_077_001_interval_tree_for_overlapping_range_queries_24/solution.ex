  test "enclosing includes an interval at both endpoints but not just past the finish" do
    tree = IntervalTree.new() |> IntervalTree.insert({1, 5})

    assert IntervalTree.enclosing(tree, 1) == [{1, 5}]
    assert IntervalTree.enclosing(tree, 5) == [{1, 5}]
    assert IntervalTree.enclosing(tree, 6) == []
    assert IntervalTree.enclosing(tree, 0) == []
  end