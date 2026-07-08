  test "start/2 re-hydrates state from DB after the in-memory map is cleared", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:42")
    {:ok, :confirmed} = StateMachine.transition(sm, "order:42", :confirm)
    {:ok, :shipped} = StateMachine.transition(sm, "order:42", :ship)

    # Start a *new* GenServer backed by the same database
    {:ok, sm2} = StateMachine.start_link(repo: StateMachine.Repo)

    # Entity was never started in sm2, so it must hydrate from DB
    assert {:ok, :shipped} = StateMachine.start(sm2, "order:42")
  end