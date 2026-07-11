  test "resume_from skips element lines without decoding or handling them", %{
    path: path,
    collector: c
  } do
    write_array(path, for(i <- 1..10, do: valid(%{"id" => i})))

    assert {:ok, stats} =
             ResumableJsonStreamer.process(path, Collector.handler(c), resume_from: 4)

    assert stats.processed == 6
    assert stats.errors == 0
    assert stats.last_index == 10
    assert Enum.map(Collector.items(c), & &1["id"]) == [5, 6, 7, 8, 9, 10]
  end