  test "queries match the surviving set after concurrent inserts and removes", %{server: s} do
    pairs =
      1..150
      |> Task.async_stream(fn i -> {i, IntervalRegistry.insert(s, {i, i + 10})} end,
        max_concurrency: 16,
        ordered: false
      )
      |> Enum.map(fn {:ok, {i, {:ok, id}}} -> {i, id} end)

    {kept, dropped} = Enum.split_with(pairs, fn {i, _id} -> rem(i, 3) == 0 end)

    dropped
    |> Task.async_stream(fn {_i, id} -> :ok = IntervalRegistry.remove(s, id) end,
      max_concurrency: 16,
      ordered: false
    )
    |> Enum.to_list()

    expected = kept |> Enum.map(fn {i, _id} -> {i, i + 10} end) |> Enum.sort()
    stabbed = Enum.filter(expected, fn {a, b} -> a <= 60 and 60 <= b end)

    assert IntervalRegistry.size(s) == length(kept)
    assert IntervalRegistry.overlapping(s, {1, 200}) == expected
    assert IntervalRegistry.enclosing(s, 60) == stabbed
    assert IntervalRegistry.stab_count(s, 60) == length(stabbed)
  end