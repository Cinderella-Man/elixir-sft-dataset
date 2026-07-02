  test "decodes different JSON value shapes", %{path: path, collector: c} do
    encoded = [
      valid(%{"kind" => "object"}),
      valid([1, 2, 3]),
      valid("a string"),
      valid(42),
      valid(true),
      valid(nil)
    ]

    write_array(path, encoded)

    assert {:ok, stats} = JsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 6
    assert stats.errors == 0

    assert Collector.items(c) == [
             %{"kind" => "object"},
             [1, 2, 3],
             "a string",
             42,
             true,
             nil
           ]
  end