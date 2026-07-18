  test "handler return values are ignored and all items still run", %{path: path} do
    write_array(path, for(i <- 1..3, do: valid(%{"id" => i})))

    parent = self()

    handler = fn item ->
      send(parent, {:seen, item["id"]})
      {:error, :handler_says_no}
    end

    assert {:ok, stats} = ParallelJsonStreamer.process(path, handler, max_concurrency: 2)

    assert stats.processed == 3
    assert stats.errors == 0
    assert_receive {:seen, 1}, 500
    assert_receive {:seen, 2}, 500
    assert_receive {:seen, 3}, 500
    refute_receive {:seen, _}, 50
  end