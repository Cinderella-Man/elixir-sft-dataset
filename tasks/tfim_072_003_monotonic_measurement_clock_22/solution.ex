    test "measure reports minute-scale advances in whole milliseconds" do
      {:ok, c} = Clock.Fake.start_link([])

      {result, elapsed} =
        Clock.measure(c, fn ->
          Clock.Fake.advance(c, minute: 1, seconds: 30)
          :long
        end)

      assert result == :long
      assert elapsed == 90_000
    end