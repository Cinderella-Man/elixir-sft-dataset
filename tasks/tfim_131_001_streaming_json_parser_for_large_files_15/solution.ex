  test "handler return values do not affect stats or streaming", %{path: path, collector: c} do
    encoded = for i <- 1..4, do: valid(%{"id" => i})
    write_array(path, encoded)

    collect = Collector.handler(c)

    handler = fn item ->
      collect.(item)
      {:error, :ignored_by_contract}
    end

    assert {:ok, stats} = JsonStreamer.process(path, handler)

    assert stats.processed == 4
    assert stats.errors == 0
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 2, 3, 4]
  end