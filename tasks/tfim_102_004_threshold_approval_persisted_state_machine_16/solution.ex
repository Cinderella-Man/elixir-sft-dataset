  test "concurrent approvals climb to the threshold exactly once" do
    {:ok, sm} = StateMachine.start_link(repo: StateMachine.Repo, required_approvals: 3)
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:cc")
    {:ok, :in_review, 0} = StateMachine.transition(sm, "cr:cc", :submit)

    tasks =
      for _ <- 1..10 do
        Task.async(fn -> StateMachine.transition(sm, "cr:cc", :approve) end)
      end

    results = Task.await_many(tasks)

    oks = Enum.filter(results, &match?({:ok, _, _}, &1))
    invalid = Enum.filter(results, &match?({:error, :invalid_transition}, &1))

    # First 3 approvals succeed (reaching the threshold), the other 7 hit the
    # terminal :approved state and are invalid.
    assert length(oks) == 3
    assert length(invalid) == 7
    assert {:ok, :approved, 3} = StateMachine.get_state(sm, "cr:cc")
  end