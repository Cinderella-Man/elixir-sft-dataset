    test "two fake clocks hold independent counters" do
      {:ok, a} = Clock.Fake.start_link(initial: 0)
      {:ok, b} = Clock.Fake.start_link(initial: 1000)

      Clock.Fake.advance(a, seconds: 1)

      assert Clock.Fake.monotonic(a, :millisecond) == 1000
      assert Clock.Fake.monotonic(b, :millisecond) == 1000
      refute Clock.Fake.monotonic(a, :second) == 2
    end