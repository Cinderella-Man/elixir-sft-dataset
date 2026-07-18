  test "enclosing at a point equal to duplicated starts returns every stored copy" do
    tree =
      IntervalTree.new()
      |> IntervalTree.insert({1, 8})
      |> IntervalTree.insert({6, 7})
      |> IntervalTree.insert({4, 4})
      |> IntervalTree.insert({10, 10})
      |> IntervalTree.insert({10, 10})

    # Both copies of {10, 10} contain 10 (s <= point <= f), so both must appear.
    assert Enum.sort(IntervalTree.enclosing(tree, 10)) == [{10, 10}, {10, 10}]
  end