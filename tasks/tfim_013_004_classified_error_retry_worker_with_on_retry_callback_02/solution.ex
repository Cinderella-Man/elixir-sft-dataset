  test "returns immediately when function succeeds on first try", %{rw: rw} do
    func = fn -> {:ok, 42} end

    assert {:ok, 42} =
             ClassifiedRetryWorker.execute(rw, func, max_retries: 3, base_delay_ms: 100)
  end