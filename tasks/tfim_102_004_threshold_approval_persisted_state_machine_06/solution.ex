  test "reject from in_review", %{sm: sm} do
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:2")
    {:ok, :in_review, 0} = StateMachine.transition(sm, "cr:2", :submit)
    {:ok, :in_review, 1} = StateMachine.transition(sm, "cr:2", :approve)
    assert {:ok, :rejected, 1} = StateMachine.transition(sm, "cr:2", :reject)
  end