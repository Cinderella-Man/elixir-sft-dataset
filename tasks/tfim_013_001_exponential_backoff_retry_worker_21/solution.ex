  test "large max_retries drives many attempts without crashing", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      Counter.increment_and_get()
      {:error, :always}
    end

    assert {:error, :max_retries_exceeded, :always} =
             RetryWorker.execute(rw, func, max_retries: 120, base_delay_ms: 1, max_delay_ms: 0)

    assert Counter.get() == 121
  end