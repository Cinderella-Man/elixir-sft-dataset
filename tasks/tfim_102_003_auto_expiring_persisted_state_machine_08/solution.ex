  test "a pending entity auto-cancels after the TTL and records an :expire transition" do
    {:ok, sm} = StateMachine.start_link(repo: @repo, pending_ttl_ms: 60)
    {:ok, :pending} = StateMachine.start(sm, "order:exp")

    Process.sleep(180)

    assert {:ok, :cancelled} = StateMachine.get_state(sm, "order:exp")
    assert {:ok, [entry]} = StateMachine.history(sm, "order:exp")
    assert entry.event == :expire
    assert entry.from_state == :pending
    assert entry.to_state == :cancelled
  end