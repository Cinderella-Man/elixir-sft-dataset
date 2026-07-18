  test "state survives GenServer restart and is recovered from DB", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:99")
    {:ok, _} = StateMachine.transition(sm, "order:99", :confirm)
    {:ok, _} = StateMachine.transition(sm, "order:99", :ship)

    # Kill the original GenServer (simulate crash/restart)
    GenServer.stop(sm)

    # Boot a fresh one backed by the same repo
    {:ok, sm2} = StateMachine.start_link(repo: StateMachine.Repo)

    # Re-hydrate from DB
    assert {:ok, :shipped} = StateMachine.start(sm2, "order:99")

    # And it should accept further valid transitions from recovered state
    assert {:ok, :delivered} = StateMachine.transition(sm2, "order:99", :deliver)
  end