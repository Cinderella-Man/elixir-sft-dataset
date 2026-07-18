  test "throughput equals processed divided by elapsed seconds", %{path: path, collector: c} do
    encoded = for i <- 1..500, do: valid(%{"id" => i})
    write_array(path, encoded)

    assert {:ok, stats} = JsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 500
    assert is_float(stats.throughput)

    expected =
      if stats.elapsed_ms == 0 or stats.elapsed_ms == 0.0 do
        0.0
      else
        stats.processed / (stats.elapsed_ms / 1000)
      end

    assert stats.throughput == expected
  end