    test "flunks with pid and liveness when the process outlives the timeout" do
      pid = spawn(fn -> Process.sleep(1_000) end)

      error =
        assert_raise ExUnit.AssertionError, fn ->
          AssertHelpers.process_exits(pid, 50)
        end

      assert error.message =~ "did not terminate"
      assert error.message =~ inspect(pid)
      assert error.message =~ "true"

      Process.exit(pid, :kill)
    end