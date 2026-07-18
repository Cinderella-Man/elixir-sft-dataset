  test "start/0 returns the raw Agent.start_link/2 result when already started" do
    assert {:error, {:already_started, pid}} = Factory.start()
    assert is_pid(pid)
  end