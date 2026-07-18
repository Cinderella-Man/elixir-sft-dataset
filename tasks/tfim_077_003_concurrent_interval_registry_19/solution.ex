  test "overlapping matches a brute-force scan over a large mixed tree", %{server: s} do
    intervals =
      for i <- 1..120 do
        start = rem(i * 37, 100)
        {start, start + rem(i * 13, 20)}
      end

    Enum.each(intervals, fn iv -> {:ok, _} = IntervalRegistry.insert(s, iv) end)
    assert IntervalRegistry.size(s) == 120

    queries = [{0, 0}, {5, 5}, {40, 50}, {-10, 3}, {99, 200}, {0, 200}, {200, 300}]

    for {qs, qf} = q <- queries do
      expected =
        intervals
        |> Enum.filter(fn {a, b} -> a <= qf and b >= qs end)
        |> Enum.sort()

      assert IntervalRegistry.overlapping(s, q) == expected
    end
  end