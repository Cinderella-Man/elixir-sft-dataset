  test "returns retries_exhausted when all retries fail with transient", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      Counter.increment_and_get()
      {:error, :transient, :still_down}
    end

    assert {:error, :retries_exhausted, :still_down} =
             ClassifiedRetryWorker.execute(rw, func, max_retries: 3, base_delay_ms: 100)

    # 1 initial + 3 retries = 4 calls
    assert Counter.get() == 4
  end