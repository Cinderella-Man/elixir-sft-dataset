  test "empty array examines nothing", %{path: path, collector: c} do
    write_array(path, [])

    assert {:ok, stats} = ResumableJsonStreamer.process(path, Collector.handler(c))
    assert stats.processed == 0
    assert stats.errors == 0
    assert stats.last_index == 0
    assert stats.aborted == false
  end