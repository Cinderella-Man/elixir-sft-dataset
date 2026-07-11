  test "approve stays in_review until the required count, then flips to approved", %{sm: sm} do
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:1")
    {:ok, :in_review, 0} = StateMachine.transition(sm, "cr:1", :submit)

    assert {:ok, :in_review, 1} = StateMachine.transition(sm, "cr:1", :approve)
    assert {:ok, :approved, 2} = StateMachine.transition(sm, "cr:1", :approve)
    assert {:ok, :approved, 2} = StateMachine.get_state(sm, "cr:1")
  end