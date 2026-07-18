  test "concurrent inserts and removes leave a consistent count", %{server: s} do
    ids =
      1..100
      |> Task.async_stream(
        fn i ->
          {:ok, id} = IntervalRegistry.insert(s, {i, i + 2})
          id
        end,
        max_concurrency: 16,
        ordered: false
      )
      |> Enum.map(fn {:ok, id} -> id end)

    assert IntervalRegistry.size(s) == 100

    to_remove = Enum.take_every(ids, 2)

    to_remove
    |> Task.async_stream(fn id -> IntervalRegistry.remove(s, id) end,
      max_concurrency: 16,
      ordered: false
    )
    |> Enum.to_list()

    assert IntervalRegistry.size(s) == 100 - length(to_remove)
  end