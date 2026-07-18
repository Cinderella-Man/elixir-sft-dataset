  test "ascending, descending and arbitrary insertion orders answer queries identically" do
    ivs = Enum.map(0..49, fn i -> {i * 3, i * 3 + 5} end)
    arbitrary = Enum.sort_by(ivs, fn {s, _f} -> rem(s * 7, 31) end)

    build = fn list ->
      Enum.reduce(list, IntervalTree.new(), fn iv, acc -> IntervalTree.insert(acc, iv) end)
    end

    asc = build.(ivs)
    desc = build.(Enum.reverse(ivs))
    arb = build.(arbitrary)

    for {qs, qf} = q <- [{0, 4}, {7, 9}, {100, 110}, {200, 200}, {-5, -1}] do
      expected = Enum.sort(Enum.filter(ivs, fn {s, f} -> s <= qf and f >= qs end))
      assert Enum.sort(IntervalTree.overlapping(asc, q)) == expected
      assert Enum.sort(IntervalTree.overlapping(desc, q)) == expected
      assert Enum.sort(IntervalTree.overlapping(arb, q)) == expected
    end

    for p <- [0, 5, 6, 150, 152, 500] do
      expected = Enum.sort(Enum.filter(ivs, fn {s, f} -> s <= p and p <= f end))
      assert Enum.sort(IntervalTree.enclosing(asc, p)) == expected
      assert Enum.sort(IntervalTree.enclosing(desc, p)) == expected
      assert Enum.sort(IntervalTree.enclosing(arb, p)) == expected
    end
  end