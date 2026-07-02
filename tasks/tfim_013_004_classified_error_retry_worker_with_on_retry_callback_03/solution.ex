  test "does not retry when function succeeds on first try", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      Counter.increment_and_get()
      {:ok, :yep}
    end

    assert {:ok, :yep} =
             ClassifiedRetryWorker.execute(rw, func, max_retries: 5, base_delay_ms: 100)

    assert Counter.get() == 1
  end