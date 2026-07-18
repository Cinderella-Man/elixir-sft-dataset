  test "pruned queries agree with brute force after scripted inserts and deletes" do
    intervals =
      for i <- 0..119 do
        s = rem(i * 37, 100)
        {s, s + rem(i * 13, 20)}
      end

    tree = build(intervals)
    to_delete = Enum.take_every(intervals, 3)

    {tree, remaining} =
      Enum.reduce(to_delete, {tree, intervals}, fn iv, {acc, rest} ->
        {:ok, acc2} = T.delete(acc, iv)
        {acc2, List.delete(rest, iv)}
      end)

    assert T.size(tree) == length(remaining)

    for qs <- 0..120//7 do
      qf = qs + 9
      expected = Enum.filter(remaining, fn {s, f} -> s <= qf and f >= qs end)
      assert Enum.sort(T.overlapping(tree, {qs, qf})) == Enum.sort(expected)
    end

    for p <- 0..120//11 do
      expected = Enum.filter(remaining, fn {s, f} -> s <= p and p <= f end)
      assert Enum.sort(T.enclosing(tree, p)) == Enum.sort(expected)
    end
  end