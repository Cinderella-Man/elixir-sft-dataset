  test "pending_count reports one item while a batch is buffered" do
    {:ok, bc} = BatchCollector.start_link(flush_interval_ms: 300)
    parent = self()

    ff = fn items ->
      send(parent, {:flushed, items})
      {:ok, items}
    end

    task = Task.async(fn -> BatchCollector.submit(bc, :pc, :only, ff, max_batch_size: 5) end)

    observed =
      Enum.reduce_while(1..200_000, 0, fn _, _ ->
        case BatchCollector.pending_count(bc, :pc) do
          0 -> {:cont, 0}
          n -> {:halt, n}
        end
      end)

    assert observed == 1
    assert_receive {:flushed, [:only]}, 1_000
    assert Task.await(task, 1_000) == {:ok, [:only]}
    assert BatchCollector.pending_count(bc, :pc) == 0
  end