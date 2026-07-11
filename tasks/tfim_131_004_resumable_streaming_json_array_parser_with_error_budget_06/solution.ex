  test "max_errors: 2 aborts on the third malformed item", %{path: path, collector: c} do
    encoded =
      for i <- 1..12 do
        if i in [2, 5, 9], do: "]][[", else: valid(%{"id" => i})
      end

    write_array(path, encoded)

    assert {:error, :too_many_errors, stats} =
             ResumableJsonStreamer.process(path, Collector.handler(c), max_errors: 2)

    assert stats.aborted == true
    assert stats.errors == 3
    assert stats.last_index == 9
    # Processed items 1, 3, 4, 6, 7, 8 (before the 3rd error at index 9).
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 3, 4, 6, 7, 8]
  end