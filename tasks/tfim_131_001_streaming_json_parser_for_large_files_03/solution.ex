  test "handler receives fully decoded items with string keys", %{path: path, collector: c} do
    encoded = for i <- 1..5, do: valid(%{"id" => i, "value" => "item-#{i}"})
    write_array(path, encoded)

    assert {:ok, _stats} = JsonStreamer.process(path, Collector.handler(c))

    expected = for i <- 1..5, do: %{"id" => i, "value" => "item-#{i}"}
    assert Collector.items(c) == expected
  end