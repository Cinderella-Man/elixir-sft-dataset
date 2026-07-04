  test "times out a slow function and retries", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      attempt = Counter.increment_and_get()

      if attempt <= 1 do
        # Simulate a hang — sleep longer than the timeout
        Process.sleep(500)
        {:ok, :should_not_reach}
      else
        {:ok, :recovered_after_timeout}
      end
    end

    assert {:ok, :recovered_after_timeout} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 3,
               base_delay_ms: 50,
               attempt_timeout_ms: 100
             )

    assert Counter.get() == 2
  end