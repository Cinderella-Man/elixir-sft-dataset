  test "concurrent inserts are all recorded consistently", %{server: s} do
    1..200
    |> Task.async_stream(fn i -> IntervalRegistry.insert(s, {i, i + 5}) end,
      max_concurrency: 20,
      ordered: false
    )
    |> Enum.to_list()

    assert IntervalRegistry.size(s) == 200

    # Intervals {i, i+5} cover point 10 iff i <= 10 <= i+5, i.e. i in 5..10 → 6 of them.
    assert IntervalRegistry.stab_count(s, 10) == 6
  end