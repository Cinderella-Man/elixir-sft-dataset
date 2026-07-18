  test "history records event, states, and approvals in order", %{sm: sm} do
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:1")
    {:ok, :in_review, 0} = StateMachine.transition(sm, "cr:1", :submit)
    {:ok, :in_review, 1} = StateMachine.transition(sm, "cr:1", :approve)
    {:ok, :approved, 2} = StateMachine.transition(sm, "cr:1", :approve)

    assert {:ok, [s, a1, a2]} = StateMachine.history(sm, "cr:1")

    assert s.event == :submit
    assert s.from_state == :draft
    assert s.to_state == :in_review
    assert s.approvals == 0

    assert a1.event == :approve
    assert a1.from_state == :in_review
    assert a1.to_state == :in_review
    assert a1.approvals == 1

    assert a2.event == :approve
    assert a2.from_state == :in_review
    assert a2.to_state == :approved
    assert a2.approvals == 2
  end