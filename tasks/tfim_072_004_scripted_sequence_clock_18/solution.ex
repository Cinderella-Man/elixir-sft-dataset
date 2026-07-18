    test "scripted reads drive a deterministic elapsed measurement" do
      script = [~U[2024-06-01 12:00:00Z], ~U[2024-06-01 12:00:42Z]]
      {:ok, clock} = Clock.Fake.start_link(script: script)
      assert Stopwatch.elapsed_seconds(clock) == 42
    end