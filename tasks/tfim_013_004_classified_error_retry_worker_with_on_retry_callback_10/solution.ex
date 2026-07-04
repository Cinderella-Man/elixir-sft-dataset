  test "on_retry callback is invoked before each retry", %{rw: rw} do
    start_supervised!({Counter, 0})
    start_supervised!({RetryLog, []})

    func = fn ->
      attempt = Counter.increment_and_get()

      if attempt <= 3 do
        {:error, :transient, :"fail_#{attempt}"}
      else
        {:ok, :done}
      end
    end

    on_retry = fn attempt, reason, delay ->
      RetryLog.record(attempt, reason, delay)
    end

    assert {:ok, :done} =
             ClassifiedRetryWorker.execute(rw, func,
               max_retries: 5,
               base_delay_ms: 100,
               on_retry: on_retry
             )

    entries = RetryLog.entries()
    assert length(entries) == 3

    # With ZeroRandom (jitter=0), delays are: 100, 200, 400
    assert Enum.at(entries, 0) == {1, :fail_1, 100}
    assert Enum.at(entries, 1) == {2, :fail_2, 200}
    assert Enum.at(entries, 2) == {3, :fail_3, 400}
  end