  test "withdraw from draft and from in_review", %{sm: sm} do
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:3")
    assert {:ok, :withdrawn, 0} = StateMachine.transition(sm, "cr:3", :withdraw)

    {:ok, :draft, 0} = StateMachine.start(sm, "cr:4")
    {:ok, :in_review, 0} = StateMachine.transition(sm, "cr:4", :submit)
    assert {:ok, :withdrawn, 0} = StateMachine.transition(sm, "cr:4", :withdraw)
  end