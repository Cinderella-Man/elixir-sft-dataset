  test "delay_ms of 0 is accepted and runs the func asynchronously, not in the caller" do
    test = self()

    # 0 is a legal, non-negative delay: "fire on the next scheduler pass".
    assert :ok = Debouncer.call("zero", 0, fn -> send(test, {:zero_ran, self()}) end)

    assert_receive {:zero_ran, runner}, 400

    # The func must never run inline in the calling process.
    refute runner == test
  end