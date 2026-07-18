  test "element lines padded with whitespace still decode", %{path: path, collector: c} do
    File.write!(path, "[\n   {\"id\": 1},  \n\t{\"id\": 2}\t\n]\n")

    assert {:ok, stats} = ResumableJsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 2
    assert stats.errors == 0
    assert stats.last_index == 2
    assert stats.aborted == false
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 2]
  end