    test "does not leave a stray :DOWN message after a timeout" do
      pid = spawn(fn -> Process.sleep(1_000) end)

      _ =
        try do
          assert_process_exits(pid, 50)
        rescue
          _ -> :ok
        end

      Process.exit(pid, :kill)

      # The monitor should have been flushed, so no :DOWN is waiting.
      assert_no_message(80)
    end