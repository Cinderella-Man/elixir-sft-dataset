  test "skips malformed entries mid-stream and keeps order of the rest", %{
    path: path,
    collector: c
  } do
    encoded =
      for i <- 1..10 do
        if i in [3, 7], do: "{not valid json", else: valid(%{"id" => i})
      end

    write_array(path, encoded)

    assert {:ok, stats} =
             ParallelJsonStreamer.process(path, Collector.handler(c), max_concurrency: 4)

    assert stats.processed == 8
    assert stats.errors == 2
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 2, 4, 5, 6, 8, 9, 10]
  end