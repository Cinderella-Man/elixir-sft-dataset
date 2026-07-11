  test "submit moves draft to in_review with count reset to 0", %{sm: sm} do
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:1")
    assert {:ok, :in_review, 0} = StateMachine.transition(sm, "cr:1", :submit)
  end