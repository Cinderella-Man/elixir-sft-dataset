  test "start/2 returns :pending at version 0 for a brand-new entity", %{sm: sm} do
    assert {:ok, :pending, 0} = StateMachine.start(sm, "order:1")
  end