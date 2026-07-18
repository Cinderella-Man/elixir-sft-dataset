  test "correct aggregates with many overlapping intervals" do
    # Interval i is [i, i+5]; a point p is covered by every i in [p-5, p].
    tree =
      Enum.reduce(0..199, T.new(), fn i, acc ->
        T.insert(acc, {i, i + 5})
      end)

    # Deep in the middle, six windows overlap.
    assert T.depth_at(tree, 100) == 6
    assert T.max_overlap(tree) == 6

    # The busiest point achieves the reported maximum overlap.
    bp = T.busiest_point(tree)
    assert T.depth_at(tree, bp) == 6
  end