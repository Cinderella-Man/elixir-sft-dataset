  test "strips only one trailing comma and keeps commas inside values", %{
    path: path,
    collector: c
  } do
    write_array(path, [valid("a,b"), valid("mid,"), valid(%{"k" => "x,"}), valid("trailing,")])

    assert {:ok, stats} =
             ParallelJsonStreamer.process(path, Collector.handler(c), max_concurrency: 4)

    assert stats.processed == 4
    assert stats.errors == 0
    assert Collector.items(c) == ["a,b", "mid,", %{"k" => "x,"}, "trailing,"]
  end