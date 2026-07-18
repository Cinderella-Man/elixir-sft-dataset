  test "start/2 re-hydrates a mid-review approval count after restart" do
    {:ok, sm} = StateMachine.start_link(repo: StateMachine.Repo, required_approvals: 3)
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:rehy")
    {:ok, :in_review, 0} = StateMachine.transition(sm, "cr:rehy", :submit)
    {:ok, :in_review, 1} = StateMachine.transition(sm, "cr:rehy", :approve)

    GenServer.stop(sm)
    {:ok, sm2} = StateMachine.start_link(repo: StateMachine.Repo, required_approvals: 3)

    assert {:ok, :in_review, 1} = StateMachine.start(sm2, "cr:rehy")
    assert {:ok, :in_review, 2} = StateMachine.transition(sm2, "cr:rehy", :approve)
    assert {:ok, :approved, 3} = StateMachine.transition(sm2, "cr:rehy", :approve)
  end