  test "approve from draft is invalid", %{sm: sm} do
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:1")
    assert {:error, :invalid_transition} = StateMachine.transition(sm, "cr:1", :approve)
    assert {:ok, :draft, 0} = StateMachine.get_state(sm, "cr:1")
  end