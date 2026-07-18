  test "default max_concurrency admits four tasks at once but not a fifth" do
    parent = self()
    start_supervised!({BoundedRunner, name: :default_runner})

    for i <- 1..5 do
      id = :"d#{i}"

      BoundedRunner.submit(:default_runner, id,
        func: fn ->
          send(parent, {:started, id, self()})

          receive do
            :go -> id
          end
        end
      )
    end

    runner = Task.async(fn -> BoundedRunner.run_all(:default_runner) end)

    pids =
      for _ <- 1..4 do
        assert_receive {:started, _id, pid}, 500
        pid
      end

    refute_receive {:started, _, _}, 200

    Enum.each(pids, &send(&1, :go))
    assert_receive {:started, _id, fifth}, 500
    send(fifth, :go)

    assert {:ok, results} = Task.await(runner, 2000)
    assert map_size(results) == 5
  end