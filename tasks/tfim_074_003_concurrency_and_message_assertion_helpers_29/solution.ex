    test "flushes the monitor so no stray :DOWN remains after a timeout" do
      pid = spawn(fn -> Process.sleep(1_000) end)

      assert_raise ExUnit.AssertionError, fn ->
        AssertHelpers.process_exits(pid, 50)
      end

      Process.exit(pid, :kill)
      # If the monitor were not flushed, a :DOWN would now be waiting.
      assert AssertHelpers.no_message(80) == :ok
    end