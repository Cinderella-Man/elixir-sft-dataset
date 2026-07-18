  test "handler return values do not affect the run", %{path: path, collector: c} do
    write_array(path, for(i <- 1..3, do: valid(%{"id" => i})))

    handler = fn item ->
      Agent.update(c, &[item | &1])
      {:error, :handler_says_no}
    end

    assert {:ok, stats} = ResumableJsonStreamer.process(path, handler)

    assert stats.processed == 3
    assert stats.errors == 0
    assert stats.aborted == false
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 2, 3]
  end