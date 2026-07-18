  test "throughput equals processed over elapsed seconds", %{path: path, collector: c} do
    write_array(path, for(i <- 1..200, do: valid(%{"id" => i})))

    assert {:ok, stats} =
             ParallelJsonStreamer.process(path, Collector.handler(c), max_concurrency: 4)

    assert stats.processed == 200
    assert is_float(stats.throughput)

    expected =
      if stats.elapsed_ms == 0 do
        0.0
      else
        stats.processed / (stats.elapsed_ms / 1000)
      end

    assert_in_delta stats.throughput, expected, 0.000001
  end