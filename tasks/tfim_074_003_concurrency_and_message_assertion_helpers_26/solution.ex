    test "returns :ok when the process terminates in time" do
      pid = spawn(fn -> Process.sleep(20) end)
      assert AssertHelpers.process_exits(pid, 500) == :ok
    end