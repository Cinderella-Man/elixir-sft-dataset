  test "permanent error after transient errors stops retries immediately", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      attempt = Counter.increment_and_get()

      case attempt do
        1 -> {:error, :transient, :flaky}
        2 -> {:error, :transient, :flaky}
        3 -> {:error, :permanent, :auth_revoked}
        _ -> {:ok, :should_not_reach}
      end
    end

    assert {:error, :permanent, :auth_revoked} =
             ClassifiedRetryWorker.execute(rw, func, max_retries: 10, base_delay_ms: 100)

    # Stopped at attempt 3 even though 10 retries were allowed
    assert Counter.get() == 3
  end