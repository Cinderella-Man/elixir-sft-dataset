    test "dispatches to Clock.Fake when given a pid, consuming the script" do
      script = [~U[2025-03-20 09:30:00Z], ~U[2025-03-20 09:31:00Z]]
      {:ok, pid} = Clock.Fake.start_link(script: script)
      assert Clock.now(pid) == Enum.at(script, 0)
      assert Clock.now(pid) == Enum.at(script, 1)
    end