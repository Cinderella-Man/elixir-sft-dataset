    test "push/2 appends more values", %{clock: clock} do
      extra = ~U[2024-01-01 01:00:00Z]
      Clock.Fake.push(clock, [extra])
      assert Clock.Fake.remaining(clock) == 4

      # Drain the original three, then the pushed one.
      Enum.each(1..3, fn _ -> Clock.Fake.now(clock) end)
      assert Clock.Fake.now(clock) == extra
    end