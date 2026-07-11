  test "reports well-formed stats on a clean run", %{path: path, collector: c} do
    write_array(path, for(i <- 1..1_000, do: valid(%{"id" => i})))

    assert {:ok, stats} = ResumableJsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 1_000
    assert stats.errors == 0
    assert is_number(stats.elapsed_ms) and stats.elapsed_ms >= 0
    assert is_float(stats.throughput) and stats.throughput >= 0.0
  end