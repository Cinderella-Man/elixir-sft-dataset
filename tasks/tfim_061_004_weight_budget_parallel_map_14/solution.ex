  test "an oversize element waits until every running element has finished" do
    parent = self()

    spawn_link(fn ->
      results =
        WeightedMap.pmap(
          [1, 10],
          fn x ->
            send(parent, {:started, x, self()})

            receive do
              :go -> x
            end
          end,
          & &1,
          4
        )

      send(parent, {:results, results})
    end)

    assert_receive {:started, 1, p1}, 1_000
    refute_receive {:started, 10, _}, 200
    send(p1, :go)
    assert_receive {:started, 10, p10}, 1_000
    send(p10, :go)
    assert_receive {:results, [1, 10]}, 1_000
  end