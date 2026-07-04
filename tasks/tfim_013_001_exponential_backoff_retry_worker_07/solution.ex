  test "max_retries of 0 means no retries at all", %{rw: rw} do
    func = fail_then_succeed(5, :nope)

    assert {:error, :max_retries_exceeded, :boom} =
             RetryWorker.execute(rw, func, max_retries: 0, base_delay_ms: 100)

    assert Counter.get() == 1
  end