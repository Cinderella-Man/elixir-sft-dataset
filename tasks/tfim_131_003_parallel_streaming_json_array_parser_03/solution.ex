  test "handler is invoked in file order despite concurrent decode", %{path: path, collector: c} do
    write_array(path, for(i <- 1..500, do: valid(%{"id" => i})))

    assert {:ok, stats} = ParallelJsonStreamer.process(path, Collector.handler(c), max_concurrency: 8)

    assert stats.processed == 500
    assert Enum.map(Collector.items(c), & &1["id"]) == Enum.to_list(1..500)
  end