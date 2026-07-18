  test "a light element does not jump ahead of a blocked heavier queue head" do
    parent = self()

    spawn_link(fn ->
      results =
        WeightedMap.pmap(
          [2, 3, 1],
          fn x ->
            send(parent, {:started, x, self()})

            receive do
              :go -> x * 10
            end
          end,
          & &1,
          3
        )

      send(parent, {:results, results})
    end)

    assert_receive {:started, 2, p2}, 1_000
    refute_receive {:started, 1, _}, 200
    send(p2, :go)
    assert_receive {:started, 3, p3}, 1_000
    send(p3, :go)
    assert_receive {:started, 1, p1}, 1_000
    send(p1, :go)
    assert_receive {:results, [20, 30, 10]}, 1_000
  end