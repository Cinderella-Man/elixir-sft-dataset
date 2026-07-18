    test "a scheduled reminder fires at the right virtual time" do
      test = self()
      {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-06-01 09:00:00Z])
      Reminder.remind_in(clock, [hours: 2], fn -> send(test, :ding) end)

      Clock.Fake.advance(clock, hours: 1)
      refute_receive :ding, 50
      Clock.Fake.advance(clock, hours: 1)
      assert_receive :ding
    end