  test "with TTL disabled a pending entity stays pending", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:stays")
    Process.sleep(120)
    assert {:ok, :pending} = StateMachine.get_state(sm, "order:stays")
    assert {:ok, []} = StateMachine.history(sm, "order:stays")
  end