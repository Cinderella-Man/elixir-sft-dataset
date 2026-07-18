  test "duplicate items each reach the handler exactly one time", %{path: path} do
    write_array(path, [valid(%{"id" => 1}), valid(%{"id" => 1})])

    parent = self()
    handler = fn item -> send(parent, {:handled, item}) end

    assert {:ok, stats} = JsonStreamer.process(path, handler)

    assert stats.processed == 2
    assert stats.errors == 0
    assert_receive {:handled, %{"id" => 1}}, 200
    assert_receive {:handled, %{"id" => 1}}, 200
    refute_receive {:handled, _}, 50
  end