  test "inserting the same interval twice returns it twice" do
    tree =
      IntervalTree.new()
      |> IntervalTree.insert({2, 8})
      |> IntervalTree.insert({2, 8})

    result = IntervalTree.overlapping(tree, {1, 10})
    assert length(result) == 2
  end