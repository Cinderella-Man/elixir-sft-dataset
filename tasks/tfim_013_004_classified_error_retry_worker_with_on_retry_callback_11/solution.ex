  test "on_retry is not called when function succeeds on first try", %{rw: rw} do
    start_supervised!({RetryLog, []})

    func = fn -> {:ok, :immediate} end

    on_retry = fn attempt, reason, delay ->
      RetryLog.record(attempt, reason, delay)
    end

    assert {:ok, :immediate} =
             ClassifiedRetryWorker.execute(rw, func,
               max_retries: 3,
               base_delay_ms: 100,
               on_retry: on_retry
             )

    assert RetryLog.entries() == []
  end