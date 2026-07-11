  test "malformed entries never invoke the handler", %{path: path, collector: c} do
    write_array(path, [
      valid(%{"id" => 1}),
      "definitely : not json",
      valid(%{"id" => 2}),
      "[1, 2,",
      valid(%{"id" => 3})
    ])

    assert {:ok, stats} =
             ParallelJsonStreamer.process(path, Collector.handler(c), max_concurrency: 4)

    assert stats.processed == 3
    assert stats.errors == 2
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 2, 3]
  end