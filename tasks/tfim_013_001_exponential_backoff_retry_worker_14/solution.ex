  test "default max_retries is 3: exactly 4 invocations, then the error", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      Counter.increment_and_get()
      {:error, :always}
    end

    assert {:error, :max_retries_exceeded, :always} =
             RetryWorker.execute(rw, func, base_delay_ms: 0)

    assert Counter.get() == 4
  end