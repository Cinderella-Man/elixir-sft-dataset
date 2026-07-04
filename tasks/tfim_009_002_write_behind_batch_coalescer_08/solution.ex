  test "batch flushes on timer when count threshold not reached" do
    {:ok, bc} = BatchCollector.start_link(flush_interval_ms: 100)

    {elapsed, result} =
      :timer.tc(fn ->
        BatchCollector.submit(bc, :timer_test, :item, fn items -> {:ok, items} end,
          max_batch_size: 100
        )
      end)

    assert result == {:ok, [:item]}
    assert elapsed >= 80_000
    assert elapsed < 300_000
  end