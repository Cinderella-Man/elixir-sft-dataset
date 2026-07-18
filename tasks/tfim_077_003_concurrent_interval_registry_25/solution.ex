  test "descending inserts stay logarithmic and query correctly" do
    {:ok, srv} = IntervalRegistry.start_link()

    task =
      Task.async(fn ->
        Enum.each(@big..1//-1, fn i -> {:ok, _} = IntervalRegistry.insert(srv, {i, i}) end)
        :inserted
      end)

    assert {:ok, :inserted} = Task.yield(task, 20_000) || Task.shutdown(task, :brutal_kill)

    assert IntervalRegistry.size(srv) == @big
    assert IntervalRegistry.stab_count(srv, 7_777) == 1
    assert IntervalRegistry.enclosing(srv, 1) == [{1, 1}]
    assert IntervalRegistry.enclosing(srv, 0) == []
    assert IntervalRegistry.overlapping(srv, {3, 6}) == [{3, 3}, {4, 4}, {5, 5}, {6, 6}]

    assert :ok = IntervalRegistry.stop(srv)
  end