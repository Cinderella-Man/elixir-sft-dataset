  test "processes every item in a well-formed file", %{path: path, collector: c} do
    write_array(path, for(i <- 1..25, do: valid(%{"id" => i})))

    assert {:ok, stats} = ParallelJsonStreamer.process(path, Collector.handler(c), max_concurrency: 4)

    assert stats.processed == 25
    assert stats.errors == 0
    assert Collector.count(c) == 25
  end