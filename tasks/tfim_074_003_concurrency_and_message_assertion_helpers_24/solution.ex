    test "fails when the process outlives the timeout" do
      pid = spawn(fn -> Process.sleep(1_000) end)

      result =
        try do
          assert_process_exits(pid, 50)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "did not terminate" or result =~ "50"

      Process.exit(pid, :kill)
    end