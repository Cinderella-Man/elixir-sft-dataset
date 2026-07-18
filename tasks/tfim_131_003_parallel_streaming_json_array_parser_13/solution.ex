  test "trims surrounding whitespace and skips blank lines", %{path: path, collector: c} do
    body =
      "[\n" <>
        "   {\"id\":1,\"value\":\"a\"},\n" <>
        "   \n" <>
        "\t{\"id\":2,\"value\":\"b\"}\n" <>
        "  ]  \n"

    File.write!(path, body)

    assert {:ok, stats} =
             ParallelJsonStreamer.process(path, Collector.handler(c), max_concurrency: 4)

    assert stats.processed == 2
    assert stats.errors == 0
    assert Collector.items(c) == [%{"id" => 1, "value" => "a"}, %{"id" => 2, "value" => "b"}]
  end