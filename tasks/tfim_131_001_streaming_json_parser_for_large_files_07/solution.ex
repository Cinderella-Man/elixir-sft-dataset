  test "handles a file that is entirely malformed", %{path: path, collector: c} do
    encoded = for _ <- 1..6, do: "}}}garbage{{{"
    write_array(path, encoded)

    assert {:ok, stats} = JsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 0
    assert stats.errors == 6
    assert Collector.count(c) == 0
  end