  test "sorted insertion of many intervals stays fast (tree is balanced)" do
    n = 20_000

    {micros, tree} =
      :timer.tc(fn ->
        Enum.reduce(1..n, T.new(), fn i, acc -> T.insert(acc, {i, i + 2}) end)
      end)

    # Interval i is [i, i+2]; point p is covered by i in [p-2, p], so the
    # stabbing number peaks at 3, first reached at point 3.
    assert T.max_overlap(tree) == 3
    assert T.busiest_point(tree) == 3
    assert T.depth_at(tree, 10_000) == 3
    assert T.depth_at(tree, n + 3) == 0

    # A balanced tree does this in well under a second; a degenerate chain
    # needs ~n^2/2 node rebuilds and blows far past this budget.
    assert div(micros, 1000) < 5_000
  end