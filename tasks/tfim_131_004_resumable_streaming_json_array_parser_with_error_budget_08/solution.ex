  test "resume_from past the end processes nothing", %{path: path, collector: c} do
    write_array(path, for(i <- 1..5, do: valid(%{"id" => i})))

    assert {:ok, stats} =
             ResumableJsonStreamer.process(path, Collector.handler(c), resume_from: 100)

    assert stats.processed == 0
    assert stats.last_index == 5
    assert Collector.count(c) == 0
  end