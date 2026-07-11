  test "required_approvals option changes the threshold" do
    {:ok, sm} = StateMachine.start_link(repo: StateMachine.Repo, required_approvals: 3)
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:t3")
    {:ok, :in_review, 0} = StateMachine.transition(sm, "cr:t3", :submit)

    assert {:ok, :in_review, 1} = StateMachine.transition(sm, "cr:t3", :approve)
    assert {:ok, :in_review, 2} = StateMachine.transition(sm, "cr:t3", :approve)
    assert {:ok, :approved, 3} = StateMachine.transition(sm, "cr:t3", :approve)
  end