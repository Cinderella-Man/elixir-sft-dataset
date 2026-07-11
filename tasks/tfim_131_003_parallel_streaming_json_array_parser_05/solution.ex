  test "works with max_concurrency: 1 and preserves order", %{path: path, collector: c} do
    write_array(path, for(i <- 1..10, do: valid(%{"id" => i})))

    assert {:ok, stats} =
             ParallelJsonStreamer.process(path, Collector.handler(c), max_concurrency: 1)

    assert stats.processed == 10
    assert Enum.map(Collector.items(c), & &1["id"]) == Enum.to_list(1..10)
  end