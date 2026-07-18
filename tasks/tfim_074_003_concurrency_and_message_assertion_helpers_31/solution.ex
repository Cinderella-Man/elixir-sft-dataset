  test "assert_process_exits failure shows the pid, its liveness and the wait" do
    pid = spawn(fn -> Process.sleep(:infinity) end)

    result =
      try do
        assert_process_exits(pid, 50)
        :no_failure
      rescue
        e in ExUnit.AssertionError -> e.message
      end

    Process.exit(pid, :kill)

    refute result == :no_failure
    assert result =~ inspect(pid)
    # Strip the pid text so its digits cannot satisfy the wait/liveness checks.
    without_pid = String.replace(result, inspect(pid), "")
    assert without_pid =~ "true"
    assert without_pid =~ "50"
  end