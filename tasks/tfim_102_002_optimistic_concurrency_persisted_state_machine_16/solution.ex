  test "start/2 re-hydrates state and version after restart", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:99")
    {:ok, :confirmed, 1} = StateMachine.transition(sm, "order:99", :confirm, 0)
    {:ok, :shipped, 2} = StateMachine.transition(sm, "order:99", :ship, 1)

    GenServer.stop(sm)
    {:ok, sm2} = StateMachine.start_link(repo: StateMachine.Repo)

    assert {:ok, :shipped, 2} = StateMachine.start(sm2, "order:99")
    assert {:ok, :delivered, 3} = StateMachine.transition(sm2, "order:99", :deliver, 2)
  end