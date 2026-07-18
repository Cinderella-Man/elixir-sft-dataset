  test "on_retry delay reflects injected non-zero jitter added to backoff" do
    start_supervised!({Counter, 0})
    start_supervised!({RetryLog, []})

    {:ok, rw2} =
      ClassifiedRetryWorker.start_link(clock: &Clock.now/0, random: fn _max -> 7 end)

    func = fn ->
      attempt = Counter.increment_and_get()
      if attempt == 1, do: {:error, :transient, :once}, else: {:ok, :ok}
    end

    on_retry = fn a, r, d -> RetryLog.record(a, r, d) end

    assert {:ok, :ok} =
             ClassifiedRetryWorker.execute(rw2, func,
               base_delay_ms: 100,
               on_retry: on_retry
             )

    # delay 100 + jitter 7 = 107
    assert RetryLog.entries() == [{1, :once, 107}]
  end