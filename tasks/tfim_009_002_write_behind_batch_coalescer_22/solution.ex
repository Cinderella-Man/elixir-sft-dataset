  test "short flush_interval_ms fires the batch automatically without any threshold hit" do
    {:ok, bc} = BatchCollector.start_link(flush_interval_ms: 25)
    parent = self()

    ff = fn items ->
      send(parent, {:auto_flushed, items})
      {:ok, items}
    end

    task = Task.async(fn -> BatchCollector.submit(bc, :auto, :solo, ff, max_batch_size: 500) end)

    # Nothing but the interval timer can flush a 1-item batch under a 500 threshold.
    assert_receive {:auto_flushed, [:solo]}, 2_000
    assert Task.await(task, 5_000) == {:ok, [:solo]}
  end