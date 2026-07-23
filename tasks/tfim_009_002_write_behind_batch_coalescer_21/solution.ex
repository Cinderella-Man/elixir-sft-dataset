  test "flush_fn receives items in submission order, not value order" do
    {:ok, bc} = BatchCollector.start_link(flush_interval_ms: 60_000)

    ff = fn items -> {:ok, items} end

    # Each item is only submitted once the previous one is confirmed buffered,
    # so submission order is fixed: 3, then 1, then 2. The values are chosen so
    # that sorted, reversed, and submission order are all different lists.
    t1 = Task.async(fn -> BatchCollector.submit(bc, :seq, 3, ff, max_batch_size: 3) end)
    assert await_pending(bc, :seq, 1) == 1

    t2 = Task.async(fn -> BatchCollector.submit(bc, :seq, 1, ff, max_batch_size: 3) end)
    assert await_pending(bc, :seq, 2) == 2

    # The third item reaches the threshold and flushes the batch.
    t3 = Task.async(fn -> BatchCollector.submit(bc, :seq, 2, ff, max_batch_size: 3) end)

    results = Task.await_many([t1, t2, t3], 5_000)

    assert Enum.all?(results, &(&1 == {:ok, [3, 1, 2]}))
  end