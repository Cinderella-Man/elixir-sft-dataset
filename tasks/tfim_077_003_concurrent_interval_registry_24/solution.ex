  test "ascending inserts stay logarithmic and query correctly" do
    {:ok, srv} = IntervalRegistry.start_link()

    task =
      Task.async(fn ->
        Enum.each(1..@big, fn i -> {:ok, _} = IntervalRegistry.insert(srv, {i, i + 1}) end)
        :inserted
      end)

    assert {:ok, :inserted} = Task.yield(task, 20_000) || Task.shutdown(task, :brutal_kill)

    assert IntervalRegistry.size(srv) == @big
    assert IntervalRegistry.stab_count(srv, 5_000) == 2
    assert IntervalRegistry.enclosing(srv, 5_000) == [{4_999, 5_000}, {5_000, 5_001}]
    assert IntervalRegistry.overlapping(srv, {1, 1}) == [{1, 2}]
    assert IntervalRegistry.enclosing(srv, @big + 1) == [{@big, @big + 1}]
    assert IntervalRegistry.stab_count(srv, @big + 2) == 0

    assert :ok = IntervalRegistry.stop(srv)
  end