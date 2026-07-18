  test "withdraw from in_review keeps a non-zero approval count unchanged" do
    {:ok, sm} = StateMachine.start_link(repo: StateMachine.Repo, required_approvals: 3)
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:wd")
    {:ok, :in_review, 0} = StateMachine.transition(sm, "cr:wd", :submit)
    {:ok, :in_review, 1} = StateMachine.transition(sm, "cr:wd", :approve)
    {:ok, :in_review, 2} = StateMachine.transition(sm, "cr:wd", :approve)

    assert {:ok, :withdrawn, 2} = StateMachine.transition(sm, "cr:wd", :withdraw)
    assert {:ok, :withdrawn, 2} = StateMachine.get_state(sm, "cr:wd")

    assert {:ok, entries} = StateMachine.history(sm, "cr:wd")
    last = List.last(entries)
    assert last.event == :withdraw
    assert last.from_state == :in_review
    assert last.to_state == :withdrawn
    assert last.approvals == 2
  end