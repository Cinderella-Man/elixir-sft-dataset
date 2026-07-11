  test "auto-expiry survives restart and re-hydrates as cancelled" do
    {:ok, sm} = StateMachine.start_link(repo: @repo, pending_ttl_ms: 50)
    {:ok, :pending} = StateMachine.start(sm, "order:rehy")
    Process.sleep(180)
    {:ok, :cancelled} = StateMachine.get_state(sm, "order:rehy")

    GenServer.stop(sm)
    {:ok, sm2} = StateMachine.start_link(repo: @repo)
    assert {:ok, :cancelled} = StateMachine.start(sm2, "order:rehy")
  end