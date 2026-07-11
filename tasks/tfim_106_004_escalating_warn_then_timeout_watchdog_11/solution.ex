  test "register raises when warn_ms is not strictly less than timeout_ms" do
    test = self()

    assert_raise ArgumentError, fn ->
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        100,
        100,
        warn_notifier(test),
        timeout_notifier(test)
      )
    end

    assert_raise ArgumentError, fn ->
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        200,
        100,
        warn_notifier(test),
        timeout_notifier(test)
      )
    end
  end