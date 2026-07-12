    test "a timer fires only once virtual time reaches its due instant", %{clock: clock} do
      test = self()
      Clock.Fake.schedule(clock, [seconds: 10], fn -> send(test, :fired) end)

      Clock.Fake.advance(clock, seconds: 5)
      refute_receive :fired, 50

      Clock.Fake.advance(clock, seconds: 5)
      assert_receive :fired
    end