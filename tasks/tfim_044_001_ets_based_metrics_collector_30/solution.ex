  test "start_link defaults the process registration name to the module itself" do
    assert is_pid(Process.whereis(Metrics))
  end