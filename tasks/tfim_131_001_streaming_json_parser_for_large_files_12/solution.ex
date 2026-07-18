  test "only one trailing comma is stripped from an element line", %{path: path, collector: c} do
    encoded = [valid("a,"), valid(%{"note" => "b,"}), valid("c,")]
    write_array(path, encoded)

    assert {:ok, stats} = JsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 3
    assert stats.errors == 0
    assert Collector.items(c) == ["a,", %{"note" => "b,"}, "c,"]
  end