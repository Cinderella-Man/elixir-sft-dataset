  test "a finishing task hands its slot to a waiting ready task" do
    parent = self()
    start_runner(2)

    for i <- 1..3 do
      id = :"slot_#{i}"

      BoundedRunner.submit(:runner, id,
        func: fn ->
          send(parent, {:started, id, self()})

          receive do
            :go -> id
          end
        end
      )
    end

    runner = Task.async(fn -> BoundedRunner.run_all(:runner) end)

    assert_receive {:started, _, first}, 500
    assert_receive {:started, _, second}, 500
    refute_receive {:started, _, _}, 200

    send(first, :go)
    assert_receive {:started, _, third}, 500

    send(second, :go)
    send(third, :go)

    assert {:ok, results} = Task.await(runner, 2000)
    assert map_size(results) == 3
  end