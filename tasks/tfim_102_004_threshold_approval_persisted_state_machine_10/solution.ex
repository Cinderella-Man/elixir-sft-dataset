  test "approved is terminal: further events are invalid", %{sm: sm} do
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:1")
    {:ok, :in_review, 0} = StateMachine.transition(sm, "cr:1", :submit)
    {:ok, :in_review, 1} = StateMachine.transition(sm, "cr:1", :approve)
    {:ok, :approved, 2} = StateMachine.transition(sm, "cr:1", :approve)

    assert {:error, :invalid_transition} = StateMachine.transition(sm, "cr:1", :approve)
    assert {:error, :invalid_transition} = StateMachine.transition(sm, "cr:1", :submit)
  end