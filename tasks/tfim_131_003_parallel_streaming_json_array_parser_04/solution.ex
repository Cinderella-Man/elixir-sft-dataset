  test "reports the effective max_concurrency", %{path: path, collector: c} do
    write_array(path, for(i <- 1..3, do: valid(%{"id" => i})))

    assert {:ok, stats} =
             ParallelJsonStreamer.process(path, Collector.handler(c), max_concurrency: 3)
    assert stats.max_concurrency == 3

    {:ok, c2} = Collector.start_link()
    assert {:ok, dstats} = ParallelJsonStreamer.process(path, Collector.handler(c2))
    assert dstats.max_concurrency == System.schedulers_online()
  end