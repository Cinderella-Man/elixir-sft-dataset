  test "assert_process_exits waits the documented default of 1000ms and reports it" do
    pid = spawn(fn -> Process.sleep(:infinity) end)

    result =
      try do
        assert_process_exits(pid)
        :no_failure
      rescue
        e in ExUnit.AssertionError -> e.message
      end

    Process.exit(pid, :kill)

    refute result == :no_failure
    assert result =~ inspect(pid)
    # Check the reported wait outside the pid text so a pid that happens to
    # contain the digits 1000 cannot satisfy the assertion.
    assert String.replace(result, inspect(pid), "") =~ "1000"
  end