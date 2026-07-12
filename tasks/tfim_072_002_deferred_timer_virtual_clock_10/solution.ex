    test "cancel returns :error for an unknown or already-fired ref", %{clock: clock} do
      ref = Clock.Fake.schedule(clock, [seconds: 1], fn -> :ok end)
      Clock.Fake.advance(clock, seconds: 2)
      assert Clock.Fake.cancel(clock, ref) == :error
      assert Clock.Fake.cancel(clock, 9999) == :error
    end