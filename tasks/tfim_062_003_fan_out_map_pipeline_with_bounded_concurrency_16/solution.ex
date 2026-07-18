  test "map stage without :max_concurrency starts every element concurrently" do
    parent = self()

    rendezvous = fn x ->
      send(parent, {:started, x, self()})

      receive do
        :go -> {:ok, x}
      end
    end

    pipeline = Pipeline.new() |> Pipeline.map_stage(:rendezvous, rendezvous)
    runner = Task.async(fn -> Pipeline.run(pipeline, [1, 2, 3, 4]) end)

    pids =
      for _ <- 1..4 do
        assert_receive {:started, _x, pid}, 2_000
        pid
      end

    Enum.each(pids, &send(&1, :go))

    assert {:ok, [1, 2, 3, 4], [%{stage: :rendezvous, type: :map, count: 4}]} =
             Task.await(runner, 5_000)
  end