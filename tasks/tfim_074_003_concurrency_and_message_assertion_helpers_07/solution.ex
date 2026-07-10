  test "process_exits waits the documented default of 1000ms and reports it" do
    pid = spawn(fn -> Process.sleep(:infinity) end)

    error =
      assert_raise ExUnit.AssertionError, fn ->
        AssertHelpers.process_exits(pid)
      end

    Process.exit(pid, :kill)

    assert error.message =~ "did not terminate"
    assert error.message =~ inspect(pid)
    # Check the reported wait outside the pid text so a pid that happens to
    # contain the digits 1000 cannot satisfy the assertion.
    assert String.replace(error.message, inspect(pid), "") =~ "1000"
  end