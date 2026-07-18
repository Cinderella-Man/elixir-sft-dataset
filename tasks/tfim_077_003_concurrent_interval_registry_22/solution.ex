  test "ids are unique across concurrent clients and not reused after removal", %{server: s} do
    ids =
      1..100
      |> Task.async_stream(fn i -> IntervalRegistry.insert(s, {i, i}) end,
        max_concurrency: 16,
        ordered: false
      )
      |> Enum.map(fn {:ok, {:ok, id}} -> id end)

    assert Enum.all?(ids, &is_integer/1)
    assert length(Enum.uniq(ids)) == 100

    Enum.each(ids, fn id -> assert :ok = IntervalRegistry.remove(s, id) end)
    assert IntervalRegistry.size(s) == 0

    {:ok, fresh} = IntervalRegistry.insert(s, {1, 1})
    refute fresh in ids
  end