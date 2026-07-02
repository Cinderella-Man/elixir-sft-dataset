  test "clean run processes everything, aborted false", %{path: path, collector: c} do
    write_array(path, for(i <- 1..25, do: valid(%{"id" => i})))

    assert {:ok, stats} = ResumableJsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 25
    assert stats.errors == 0
    assert stats.last_index == 25
    assert stats.aborted == false
    assert Collector.count(c) == 25
  end