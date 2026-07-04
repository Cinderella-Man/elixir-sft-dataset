  test "succeeds on the very last retry", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      attempt = Counter.increment_and_get()

      if attempt <= 3 do
        {:error, :transient, :timeout}
      else
        {:ok, :last_chance}
      end
    end

    assert {:ok, :last_chance} =
             ClassifiedRetryWorker.execute(rw, func, max_retries: 3, base_delay_ms: 100)

    assert Counter.get() == 4
  end