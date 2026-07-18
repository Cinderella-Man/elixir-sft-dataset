  test "negative max_retries invokes func once then errors immediately", %{rw: rw} do
    func = fail_then_succeed(5, :never)

    assert {:error, :max_retries_exceeded, :boom} =
             RetryWorker.execute(rw, func, max_retries: -1, base_delay_ms: 100)

    assert Counter.get() == 1
  end