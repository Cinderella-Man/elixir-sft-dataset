  test "max_retries of 0 means no retries for transient errors", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      Counter.increment_and_get()
      {:error, :transient, :boom}
    end

    assert {:error, :retries_exhausted, :boom} =
             ClassifiedRetryWorker.execute(rw, func, max_retries: 0, base_delay_ms: 100)

    assert Counter.get() == 1
  end