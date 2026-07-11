  test "max_errors: 0 aborts on the first malformed item", %{path: path, collector: c} do
    encoded =
      for i <- 1..10 do
        if i == 4, do: "garbage(((", else: valid(%{"id" => i})
      end

    write_array(path, encoded)

    assert {:error, :too_many_errors, stats} =
             ResumableJsonStreamer.process(path, Collector.handler(c), max_errors: 0)

    assert stats.aborted == true
    assert stats.errors == 1
    assert stats.processed == 3
    assert stats.last_index == 4
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 2, 3]
  end