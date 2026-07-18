  test "ascending bulk inserts, queries and deletes stay logarithmic" do
    n = 20_000

    tree = Enum.reduce(1..n, T.new(), fn i, acc -> T.insert(acc, {i, i + 1}) end)

    assert T.size(tree) == n
    assert Enum.sort(T.enclosing(tree, 10_000)) == [{9_999, 10_000}, {10_000, 10_001}]

    assert Enum.sort(T.overlapping(tree, {17_000, 17_001})) ==
             [{16_999, 17_000}, {17_000, 17_001}, {17_001, 17_002}]

    tree =
      Enum.reduce(1..n, tree, fn i, acc ->
        {:ok, acc2} = T.delete(acc, {i, i + 1})
        acc2
      end)

    assert T.size(tree) == 0
    assert [] = T.overlapping(tree, {1, n})
  end