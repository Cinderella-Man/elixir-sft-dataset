  test "each of the four rebalancing shapes keeps every interval queryable" do
    cases = [
      {"left-left", [{30, 31}, {20, 21}, {10, 11}]},
      {"left-right", [{30, 31}, {10, 11}, {20, 21}]},
      {"right-right", [{10, 11}, {20, 21}, {30, 31}]},
      {"right-left", [{10, 11}, {30, 31}, {20, 21}]}
    ]

    for {label, ivs} <- cases do
      tree = build(ivs)

      assert Enum.sort(IntervalTree.overlapping(tree, {0, 40})) == Enum.sort(ivs), label
      assert IntervalTree.overlapping(tree, {40, 50}) == [], label
      assert IntervalTree.overlapping(tree, {0, 9}) == [], label

      for {s, f} <- ivs do
        assert IntervalTree.enclosing(tree, s) == [{s, f}], label
        assert IntervalTree.enclosing(tree, f) == [{s, f}], label
        assert IntervalTree.enclosing(tree, s - 1) == [], label
        assert IntervalTree.enclosing(tree, f + 1) == [], label
        assert IntervalTree.overlapping(tree, {s, f}) == [{s, f}], label
      end
    end
  end