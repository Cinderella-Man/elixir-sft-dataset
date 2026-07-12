    test "hands out scripted values in order, one per call", %{clock: clock, script: script} do
      assert Enum.map(script, fn _ -> Clock.Fake.now(clock) end) == script
    end