  test "default max_batch_size threshold is 10" do
    {:ok, bc} = BatchCollector.start_link(flush_interval_ms: 60_000)
    parent = self()

    ff = fn items ->
      send(parent, {:flushed, length(items)})
      {:ok, items}
    end

    for i <- 1..9 do
      Task.async(fn -> BatchCollector.submit(bc, :d, i, ff) end)
    end

    buffered =
      Enum.reduce_while(1..200_000, 0, fn _, _ ->
        case BatchCollector.pending_count(bc, :d) do
          9 -> {:halt, 9}
          _ -> {:cont, 0}
        end
      end)

    assert buffered == 9
    # 9 < default 10: no flush from the (60s) timer nor from the threshold.
    refute_receive {:flushed, _}, 100

    Task.async(fn -> BatchCollector.submit(bc, :d, 10, ff) end)
    assert_receive {:flushed, 10}, 1_000
  end