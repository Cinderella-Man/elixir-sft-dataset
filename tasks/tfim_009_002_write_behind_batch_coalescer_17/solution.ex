  test "no second flush occurs after the count threshold triggers a flush" do
    {:ok, bc} = BatchCollector.start_link(flush_interval_ms: 200)
    parent = self()

    ff = fn items ->
      send(parent, {:flushed, length(items)})
      {:ok, items}
    end

    t1 = Task.async(fn -> BatchCollector.submit(bc, :once, :a, ff, max_batch_size: 2) end)
    t2 = Task.async(fn -> BatchCollector.submit(bc, :once, :b, ff, max_batch_size: 2) end)

    [r1, r2] = Task.await_many([t1, t2], 1_000)
    assert {:ok, items} = r1
    assert length(items) == 2
    assert r1 == r2

    assert_receive {:flushed, 2}, 1_000
    # The 200ms timer deadline passes here; it must not cause a second flush.
    refute_receive {:flushed, _}, 600
  end