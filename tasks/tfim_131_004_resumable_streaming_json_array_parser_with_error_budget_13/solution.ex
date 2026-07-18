  test "blank lines are not element lines for indexing or resume", %{path: path, collector: c} do
    File.write!(path, "[\n\n{\"id\": 1},\n\n\n{\"id\": 2},\n{\"id\": 3}\n\n]\n")

    assert {:ok, stats} =
             ResumableJsonStreamer.process(path, Collector.handler(c), resume_from: 1)

    assert stats.processed == 2
    assert stats.errors == 0
    assert stats.last_index == 3
    assert stats.aborted == false
    assert Enum.map(Collector.items(c), & &1["id"]) == [2, 3]
  end