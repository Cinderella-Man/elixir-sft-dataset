  test "descending insertion of many intervals stays fast (tree is balanced)" do
    n = 20_000

    {micros, tree} =
      :timer.tc(fn ->
        Enum.reduce(n..1//-1, T.new(), fn i, acc -> T.insert(acc, {i, i + 2}) end)
      end)

    assert T.max_overlap(tree) == 3
    assert T.busiest_point(tree) == 3
    assert T.depth_at(tree, 12_345) == 3
    assert div(micros, 1000) < 5_000
  end