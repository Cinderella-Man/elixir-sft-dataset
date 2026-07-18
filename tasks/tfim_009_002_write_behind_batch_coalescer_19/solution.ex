  test "keys apply their own max_batch_size thresholds independently" do
    {:ok, bc} = BatchCollector.start_link(flush_interval_ms: 60_000)
    parent = self()

    ff = fn items ->
      send(parent, {:flushed, hd(items), length(items)})
      {:ok, items}
    end

    Task.async(fn -> BatchCollector.submit(bc, :b, :b1, ff, max_batch_size: 3) end)
    Task.async(fn -> BatchCollector.submit(bc, :b, :b2, ff, max_batch_size: 3) end)
    Task.async(fn -> BatchCollector.submit(bc, :a, :a1, ff, max_batch_size: 2) end)
    Task.async(fn -> BatchCollector.submit(bc, :a, :a2, ff, max_batch_size: 2) end)

    buffered_b =
      Enum.reduce_while(1..200_000, 0, fn _, _ ->
        case BatchCollector.pending_count(bc, :b) do
          2 -> {:halt, 2}
          _ -> {:cont, 0}
        end
      end)

    assert buffered_b == 2
    # :a hits its own threshold of 2 and flushes...
    assert_receive {:flushed, aa, 2}, 1_000
    assert aa in [:a1, :a2]
    # ...while :b (threshold 3) stays buffered and must not flush.
    refute_receive {:flushed, _bb, _}, 300

    # Drain :b via its own threshold so no callers block forever.
    Task.async(fn -> BatchCollector.submit(bc, :b, :b3, ff, max_batch_size: 3) end)
    assert_receive {:flushed, cc, 3}, 1_000
    assert cc in [:b1, :b2]
  end