  test "malformed first and last elements do not abort processing", %{path: path, collector: c} do
    write_array(path, ["{oops", valid(%{"id" => 1}), valid(%{"id" => 2}), "nope}"])

    assert {:ok, stats} =
             ParallelJsonStreamer.process(path, Collector.handler(c), max_concurrency: 4)

    assert stats.processed == 2
    assert stats.errors == 2
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 2]
  end