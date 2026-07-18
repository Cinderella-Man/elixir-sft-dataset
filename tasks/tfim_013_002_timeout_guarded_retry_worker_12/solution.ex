  test "timeout on first attempt then error then success", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      attempt = Counter.increment_and_get()

      case attempt do
        1 ->
          Process.sleep(500)
          {:ok, :too_slow}

        2 ->
          {:error, :transient_failure}

        _ ->
          {:ok, :finally}
      end
    end

    assert {:ok, :finally} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 5,
               base_delay_ms: 50,
               attempt_timeout_ms: 100
             )

    assert Counter.get() == 3
  end