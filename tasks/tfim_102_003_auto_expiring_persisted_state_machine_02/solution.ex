  test "start/2 returns :pending for a brand-new entity", %{sm: sm} do
    assert {:ok, :pending} = StateMachine.start(sm, "order:1")
  end