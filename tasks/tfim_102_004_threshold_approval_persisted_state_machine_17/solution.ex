  test "rejected and withdrawn are terminal and other bad pairs are invalid", %{sm: sm} do
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:inv1")
    assert {:error, :invalid_transition} = StateMachine.transition(sm, "cr:inv1", :reject)
    {:ok, :in_review, 0} = StateMachine.transition(sm, "cr:inv1", :submit)
    assert {:error, :invalid_transition} = StateMachine.transition(sm, "cr:inv1", :submit)
    {:ok, :rejected, 0} = StateMachine.transition(sm, "cr:inv1", :reject)

    assert {:error, :invalid_transition} = StateMachine.transition(sm, "cr:inv1", :approve)
    assert {:error, :invalid_transition} = StateMachine.transition(sm, "cr:inv1", :submit)
    assert {:error, :invalid_transition} = StateMachine.transition(sm, "cr:inv1", :withdraw)
    assert {:ok, :rejected, 0} = StateMachine.get_state(sm, "cr:inv1")

    {:ok, :draft, 0} = StateMachine.start(sm, "cr:inv2")
    {:ok, :withdrawn, 0} = StateMachine.transition(sm, "cr:inv2", :withdraw)
    assert {:error, :invalid_transition} = StateMachine.transition(sm, "cr:inv2", :submit)
    assert {:error, :invalid_transition} = StateMachine.transition(sm, "cr:inv2", :approve)
    assert {:ok, :withdrawn, 0} = StateMachine.get_state(sm, "cr:inv2")
  end