    test "freeze then advance", %{clock: clock} do
      pivot = ~U[2030-07-04 08:00:00Z]
      Clock.Fake.freeze(clock, pivot)
      Clock.Fake.advance(clock, seconds: 100)
      expected = DateTime.add(pivot, 100, :second)
      assert Clock.Fake.now(clock) == expected
    end