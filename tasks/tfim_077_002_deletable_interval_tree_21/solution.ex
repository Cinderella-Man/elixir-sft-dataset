  test "size grows by exactly one per insert and shrinks by exactly one per delete" do
    intervals = for i <- 1..40, do: {rem(i * 7, 40), rem(i * 7, 40) + 2}

    {tree, count} =
      Enum.reduce(intervals, {T.new(), 0}, fn iv, {acc, n} ->
        acc2 = T.insert(acc, iv)
        assert T.size(acc2) == n + 1
        {acc2, n + 1}
      end)

    assert count == 40
    assert T.size(tree) == 40

    # A failed delete must not change the count.
    assert {:error, :not_found} = T.delete(tree, {1000, 1001})
    assert T.size(tree) == 40

    {empty, left_over} =
      Enum.reduce(intervals, {tree, 40}, fn iv, {acc, n} ->
        {:ok, acc2} = T.delete(acc, iv)
        assert T.size(acc2) == n - 1
        {acc2, n - 1}
      end)

    assert left_over == 0
    assert T.size(empty) == 0
    assert [] = T.overlapping(empty, {-100, 100})
  end