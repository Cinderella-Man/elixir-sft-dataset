  test "queries match a brute-force scan after every single insertion" do
    ivs = arbitrary(60)

    _ =
      Enum.reduce(ivs, {IntervalTree.new(), []}, fn iv, {tree, seen} ->
        tree = IntervalTree.insert(tree, iv)
        seen = [iv | seen]

        for p <- [0, 5, 155, 300, 595, 700] do
          expected = seen |> Enum.filter(fn {s, f} -> s <= p and p <= f end) |> Enum.sort()
          assert Enum.sort(IntervalTree.enclosing(tree, p)) == expected
        end

        {tree, seen}
      end)
  end