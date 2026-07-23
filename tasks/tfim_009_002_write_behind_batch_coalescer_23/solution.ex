  test "a stale timer never flushes the key's successor batch early" do
    # Batch 1 for "k" flushes via the size threshold, but its timer message is
    # engineered to already be in flight. Batch 2 (same key) must keep
    # coalescing until ITS OWN timer/threshold — the stale message may not
    # flush it early with a single item.
    test_pid = self()
    flush_fn = fn items -> send(test_pid, {:flushed, items}) end

    {:ok, co} = BatchCollector.start_link(flush_interval_ms: 60)

    # Fill batch 1 to the threshold exactly as its timer nears firing.
    t1 = Task.async(fn -> BatchCollector.submit(co, "k", :a1, flush_fn, max_batch_size: 2) end)
    Process.sleep(55)
    t2 = Task.async(fn -> BatchCollector.submit(co, "k", :a2, flush_fn, max_batch_size: 2) end)
    assert_receive {:flushed, batch1}, 500
    assert Enum.sort(batch1) == [:a1, :a2]
    Task.await(t1)
    Task.await(t2)

    # Immediately open batch 2; the stale batch-1 timer fires ~now.
    t3 = Task.async(fn -> BatchCollector.submit(co, "k", :b1, flush_fn, max_batch_size: 10) end)

    # Within the stale window nothing may flush; batch 2's own 60ms timer
    # eventually flushes exactly [:b1].
    refute_receive {:flushed, _}, 40
    assert_receive {:flushed, [:b1]}, 500
    Task.await(t3)
  end