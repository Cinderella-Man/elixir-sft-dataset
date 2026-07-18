  test "concurrent transitions on different entities all succeed", %{sm: sm} do
    for i <- 1..10, do: StateMachine.start(sm, "order:par:#{i}")

    tasks =
      for i <- 1..10 do
        Task.async(fn -> StateMachine.transition(sm, "order:par:#{i}", :confirm, 0) end)
      end

    results = Task.await_many(tasks)
    assert Enum.all?(results, &match?({:ok, :confirmed, 1}, &1))
  end