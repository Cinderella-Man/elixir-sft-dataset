  test "malformed entries never invoke the handler", %{path: path, collector: c} do
    encoded = [
      valid(%{"id" => 1}),
      "definitely : not json",
      valid(%{"id" => 2}),
      "[1, 2,",
      valid(%{"id" => 3})
    ]

    write_array(path, encoded)

    assert {:ok, stats} = JsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 3
    assert stats.errors == 2
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 2, 3]
  end