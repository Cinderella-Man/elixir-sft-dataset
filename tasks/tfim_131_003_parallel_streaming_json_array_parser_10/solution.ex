  test "reports well-formed stats", %{path: path, collector: c} do
    write_array(path, for(i <- 1..1_000, do: valid(%{"id" => i})))

    assert {:ok, stats} =
             ParallelJsonStreamer.process(path, Collector.handler(c), max_concurrency: 8)

    assert stats.processed == 1_000
    assert stats.errors == 0
    assert is_number(stats.elapsed_ms) and stats.elapsed_ms >= 0
    assert is_float(stats.throughput) and stats.throughput >= 0.0
  end