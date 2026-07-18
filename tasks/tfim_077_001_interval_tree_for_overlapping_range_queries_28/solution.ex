  test "every insertion permutation of a small set answers queries identically" do
    ivs = [{1, 10}, {2, 3}, {5, 20}, {5, 5}, {12, 14}, {30, 31}]
    probes = [0, 1, 2, 4, 5, 10, 11, 13, 20, 21, 30, 32]

    for order <- permutations(ivs) do
      tree = build(order)

      assert Enum.sort(IntervalTree.overlapping(tree, {0, 100})) == Enum.sort(ivs)

      for p <- probes do
        expected = ivs |> Enum.filter(fn {s, f} -> s <= p and p <= f end) |> Enum.sort()
        assert Enum.sort(IntervalTree.enclosing(tree, p)) == expected
        assert Enum.sort(IntervalTree.overlapping(tree, {p, p})) == expected
      end
    end
  end