  test "on_retry is not called on permanent error", %{rw: rw} do
    start_supervised!({RetryLog, []})

    func = fn -> {:error, :permanent, :fatal} end

    on_retry = fn attempt, reason, delay ->
      RetryLog.record(attempt, reason, delay)
    end

    assert {:error, :permanent, :fatal} =
             ClassifiedRetryWorker.execute(rw, func,
               max_retries: 3,
               base_delay_ms: 100,
               on_retry: on_retry
             )

    assert RetryLog.entries() == []
  end