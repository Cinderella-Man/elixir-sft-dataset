  test "permanent error returns immediately without retry", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      Counter.increment_and_get()
      {:error, :permanent, :invalid_input}
    end

    assert {:error, :permanent, :invalid_input} =
             ClassifiedRetryWorker.execute(rw, func, max_retries: 5, base_delay_ms: 100)

    # Only called once — no retries
    assert Counter.get() == 1
  end