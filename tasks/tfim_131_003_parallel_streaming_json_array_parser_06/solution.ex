  test "decodes different JSON value shapes in order", %{path: path, collector: c} do
    write_array(path, [
      valid(%{"kind" => "object"}),
      valid([1, 2, 3]),
      valid("a string"),
      valid(42),
      valid(true),
      valid(nil)
    ])

    assert {:ok, stats} =
             ParallelJsonStreamer.process(path, Collector.handler(c), max_concurrency: 4)

    assert stats.processed == 6

    assert Collector.items(c) == [
             %{"kind" => "object"},
             [1, 2, 3],
             "a string",
             42,
             true,
             nil
           ]
  end