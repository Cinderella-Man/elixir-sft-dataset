  test "concurrent transitions on the same entity serialize without corruption", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:concurrent")

    # Fire many concurrent callers; only the first :confirm should succeed,
    # the rest should get :invalid_transition (already confirmed) or
    # :invalid_transition (not a valid event from :pending).
    tasks =
      for _ <- 1..20 do
        Task.async(fn ->
          StateMachine.transition(sm, "order:concurrent", :confirm)
        end)
      end

    results = Task.await_many(tasks)

    oks = Enum.filter(results, &match?({:ok, _}, &1))
    errors = Enum.filter(results, &match?({:error, :invalid_transition}, &1))

    # Exactly one transition should have succeeded
    assert length(oks) == 1
    assert {:ok, :confirmed} = hd(oks)

    # All others should have gotten :invalid_transition
    assert length(errors) == 19
  end