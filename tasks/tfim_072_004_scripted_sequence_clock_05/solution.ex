    test "reset/1 rewinds the cursor", %{clock: clock, script: script} do
      Enum.each(script, fn _ -> Clock.Fake.now(clock) end)
      assert Clock.Fake.remaining(clock) == 0

      Clock.Fake.reset(clock)
      assert Clock.Fake.remaining(clock) == 3
      assert Clock.Fake.now(clock) == hd(script)
    end