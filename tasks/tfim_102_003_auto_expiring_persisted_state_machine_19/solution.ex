  test "the :name option registers the server so the API can be driven by name" do
    {:ok, pid} = StateMachine.start_link(repo: @repo, name: :sm_named_server)

    assert Process.whereis(:sm_named_server) == pid
    assert {:ok, :pending} = StateMachine.start(:sm_named_server, "order:named")
    assert {:ok, :confirmed} = StateMachine.transition(:sm_named_server, "order:named", :confirm)
    assert {:ok, :confirmed} = StateMachine.get_state(:sm_named_server, "order:named")
  end