  test "returns timeout as last reason when all attempts time out", %{rw: rw} do
    func = fn ->
      Process.sleep(500)
      {:ok, :never_reaches}
    end

    assert {:error, :max_retries_exceeded, :timeout} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 2,
               base_delay_ms: 50,
               attempt_timeout_ms: 50
             )
  end