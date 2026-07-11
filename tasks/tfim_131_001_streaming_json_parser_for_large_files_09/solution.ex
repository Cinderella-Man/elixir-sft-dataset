  test "reports well-formed stats", %{path: path, collector: c} do
    encoded = for i <- 1..1_000, do: valid(%{"id" => i})
    write_array(path, encoded)

    assert {:ok, stats} = JsonStreamer.process(path, Collector.handler(c))

    assert is_integer(stats.processed) and stats.processed == 1_000
    assert is_integer(stats.errors) and stats.errors == 0

    assert is_number(stats.elapsed_ms)
    assert stats.elapsed_ms >= 0

    assert is_float(stats.throughput)
    assert stats.throughput >= 0.0
  end