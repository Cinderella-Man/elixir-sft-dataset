  test "a still-running slow func does not hold back another key's func" do
    test = self()

    Debouncer.call(:slow_a, 20, fn ->
      send(test, {:a_started, self()})

      receive do
        :release -> send(test, :a_done)
      after
        2_000 -> :a_timeout
      end
    end)

    Debouncer.call(:quick_b, 40, notify(:b_ran))

    assert_receive {:a_started, runner}, 400
    # :a is still parked inside its receive here — :b must fire anyway.
    assert_receive :b_ran, 400

    send(runner, :release)
    assert_receive :a_done, 400
  end