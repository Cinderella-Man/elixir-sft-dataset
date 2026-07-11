  test "start/2 returns :draft with 0 approvals for a brand-new entity", %{sm: sm} do
    assert {:ok, :draft, 0} = StateMachine.start(sm, "cr:1")
  end