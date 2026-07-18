    test "passes when the process terminates in time" do
      pid = spawn(fn -> Process.sleep(20) end)
      assert_process_exits(pid, 500)
    end