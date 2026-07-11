  test "skips a malformed entry mid-stream and continues", %{path: path, collector: c} do
    encoded =
      for i <- 1..10 do
        if i in [3, 7], do: "{not valid json", else: valid(%{"id" => i})
      end

    write_array(path, encoded)

    assert {:ok, stats} = JsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 8
    assert stats.errors == 2

    ids = Enum.map(Collector.items(c), & &1["id"])
    assert ids == [1, 2, 4, 5, 6, 8, 9, 10]
  end