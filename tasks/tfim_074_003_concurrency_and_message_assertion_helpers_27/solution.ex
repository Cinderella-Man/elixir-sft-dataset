    test "returns :ok immediately for an already-dead process" do
      pid = spawn(fn -> :ok end)
      Process.sleep(20)
      refute Process.alive?(pid)
      assert AssertHelpers.process_exits(pid, 200) == :ok
    end