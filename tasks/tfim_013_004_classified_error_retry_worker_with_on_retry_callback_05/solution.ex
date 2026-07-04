  test "retries transient errors and succeeds", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      attempt = Counter.increment_and_get()

      if attempt <= 3 do
        {:error, :transient, :service_unavailable}
      else
        {:ok, :recovered}
      end
    end

    assert {:ok, :recovered} =
             ClassifiedRetryWorker.execute(rw, func, max_retries: 5, base_delay_ms: 100)

    assert Counter.get() == 4
  end