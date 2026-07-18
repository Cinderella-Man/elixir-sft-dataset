    test "two scripted clocks advance independently" do
      {:ok, a} =
        Clock.Fake.start_link(script: [~U[2020-01-01 00:00:00Z], ~U[2020-01-01 00:00:01Z]])

      {:ok, b} =
        Clock.Fake.start_link(script: [~U[2099-01-01 00:00:00Z], ~U[2099-01-01 00:00:01Z]])

      assert Clock.Fake.now(a) == ~U[2020-01-01 00:00:00Z]
      # b's cursor is untouched.
      assert Clock.Fake.remaining(b) == 2
      assert Clock.Fake.now(b) == ~U[2099-01-01 00:00:00Z]
    end