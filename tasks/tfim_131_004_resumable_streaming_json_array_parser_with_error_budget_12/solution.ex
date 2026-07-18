  test "max_errors: 2 with exactly two malformed items finishes cleanly", %{
    path: path,
    collector: c
  } do
    encoded =
      for i <- 1..8 do
        if i in [2, 5], do: "{{{not json", else: valid(%{"id" => i})
      end

    write_array(path, encoded)

    assert {:ok, stats} =
             ResumableJsonStreamer.process(path, Collector.handler(c), max_errors: 2)

    assert stats.aborted == false
    assert stats.errors == 2
    assert stats.processed == 6
    assert stats.last_index == 8
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 3, 4, 6, 7, 8]
  end