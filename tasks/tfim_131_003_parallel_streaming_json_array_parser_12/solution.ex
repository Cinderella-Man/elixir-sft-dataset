  test "identical repeated items each invoke the handler exactly once", %{
    path: path,
    collector: c
  } do
    write_array(path, for(_ <- 1..3, do: valid(%{"id" => 7, "value" => "same"})))

    assert {:ok, stats} =
             ParallelJsonStreamer.process(path, Collector.handler(c), max_concurrency: 4)

    assert stats.processed == 3
    assert stats.errors == 0

    assert Collector.items(c) == [
             %{"id" => 7, "value" => "same"},
             %{"id" => 7, "value" => "same"},
             %{"id" => 7, "value" => "same"}
           ]
  end