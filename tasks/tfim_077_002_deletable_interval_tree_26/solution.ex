  test "descending bulk inserts followed by descending deletes stay logarithmic" do
    n = 20_000

    tree = Enum.reduce(n..1//-1, T.new(), fn i, acc -> T.insert(acc, {i, i}) end)
    assert T.size(tree) == n
    assert [{4_242, 4_242}] = T.enclosing(tree, 4_242)

    tree =
      Enum.reduce(n..1//-1, tree, fn i, acc ->
        {:ok, acc2} = T.delete(acc, {i, i})
        acc2
      end)

    assert T.size(tree) == 0
    assert [] = T.enclosing(tree, 4_242)
  end