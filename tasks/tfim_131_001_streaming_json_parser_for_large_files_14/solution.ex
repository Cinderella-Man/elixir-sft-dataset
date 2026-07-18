  test "indented element lines are trimmed before decoding", %{path: path, collector: c} do
    File.write!(path, "  [  \n\t{\"id\":1},  \n   {\"id\":2}\t\n  ]  \n")

    assert {:ok, stats} = JsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 2
    assert stats.errors == 0
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 2]
  end