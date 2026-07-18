  test "invalid transition writes nothing", %{sm: sm} do
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:1")
    {:error, :invalid_transition} = StateMachine.transition(sm, "cr:1", :approve)
    assert {:ok, []} = StateMachine.history(sm, "cr:1")
  end