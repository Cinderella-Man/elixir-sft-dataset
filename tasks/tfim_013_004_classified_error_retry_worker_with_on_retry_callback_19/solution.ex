  test "default max_retries permits exactly three transient retries", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      Counter.increment_and_get()
      {:error, :transient, :always_down}
    end

    assert {:error, :retries_exhausted, :always_down} =
             ClassifiedRetryWorker.execute(rw, func, base_delay_ms: 1)

    # 1 initial + 3 default retries = 4 calls
    assert Counter.get() == 4
  end