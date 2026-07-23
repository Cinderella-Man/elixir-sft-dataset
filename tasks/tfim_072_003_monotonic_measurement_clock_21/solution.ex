    test "singular unit keys advance identically to their plural forms" do
      {:ok, singular} = Clock.Fake.start_link([])
      {:ok, plural} = Clock.Fake.start_link([])

      Clock.Fake.advance(singular, microsecond: 7, millisecond: 3, second: 5)
      Clock.Fake.advance(singular, minute: 2, hour: 1)

      Clock.Fake.advance(plural, microseconds: 7, milliseconds: 3, seconds: 5)
      Clock.Fake.advance(plural, minutes: 2, hours: 1)

      assert Clock.Fake.monotonic(singular, :microsecond) == 3_725_003_007

      assert Clock.Fake.monotonic(singular, :microsecond) ==
               Clock.Fake.monotonic(plural, :microsecond)
    end