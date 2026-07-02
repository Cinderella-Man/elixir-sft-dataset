  test "processes every item in a well-formed file", %{path: path, collector: c} do
    encoded = for i <- 1..25, do: valid(%{"id" => i})
    write_array(path, encoded)

    assert {:ok, stats} = JsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 25
    assert stats.errors == 0
    assert Collector.count(c) == 25
  end