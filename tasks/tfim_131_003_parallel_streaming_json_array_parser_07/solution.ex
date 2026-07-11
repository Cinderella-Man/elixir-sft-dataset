  test "empty array yields zero processed and zero errors", %{path: path, collector: c} do
    write_array(path, [])

    assert {:ok, stats} = ParallelJsonStreamer.process(path, Collector.handler(c))
    assert stats.processed == 0
    assert stats.errors == 0
    assert Collector.count(c) == 0
  end