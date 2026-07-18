  test "start_link/1 registers the server under the given :name" do
    name = :"sm_named_#{System.unique_integer([:positive])}"
    {:ok, pid} = StateMachine.start_link(repo: StateMachine.Repo, name: name)

    assert Process.whereis(name) == pid
    assert {:ok, :draft, 0} = StateMachine.start(name, "cr:named")
    assert {:ok, :in_review, 0} = StateMachine.transition(name, "cr:named", :submit)
    assert {:ok, :in_review, 0} = StateMachine.get_state(name, "cr:named")
  end