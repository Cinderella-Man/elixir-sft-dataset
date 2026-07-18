  test "blank lines are skipped without counting as errors", %{path: path, collector: c} do
    File.write!(path, "[\n\n{\"id\":1},\n   \n{\"id\":2}\n\n]\n")

    assert {:ok, stats} = JsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 2
    assert stats.errors == 0
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 2]
  end