  test "confirming before the TTL prevents auto-expiry" do
    {:ok, sm} = StateMachine.start_link(repo: @repo, pending_ttl_ms: 100)
    {:ok, :pending} = StateMachine.start(sm, "order:safe")
    {:ok, :confirmed} = StateMachine.transition(sm, "order:safe", :confirm)

    Process.sleep(200)

    # Expiry check fires but the entity is no longer pending, so it is a no-op.
    assert {:ok, :confirmed} = StateMachine.get_state(sm, "order:safe")
    assert {:ok, [%{event: :confirm}]} = StateMachine.history(sm, "order:safe")
  end