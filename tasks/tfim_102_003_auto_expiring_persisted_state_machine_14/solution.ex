  test "concurrent transitions on the same entity serialize", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:cc")

    tasks =
      for _ <- 1..20 do
        Task.async(fn -> StateMachine.transition(sm, "order:cc", :confirm) end)
      end

    results = Task.await_many(tasks)
    oks = Enum.filter(results, &match?({:ok, :confirmed}, &1))
    errors = Enum.filter(results, &match?({:error, :invalid_transition}, &1))

    assert length(oks) == 1
    assert length(errors) == 19
  end