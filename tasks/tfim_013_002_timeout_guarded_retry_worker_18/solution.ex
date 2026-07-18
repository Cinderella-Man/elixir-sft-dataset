  test "zero delay waits nothing rather than a millisecond per retry" do
    retries = 400
    worker = start_supervised!({TimeoutRetryWorker, [random: fn delay -> -delay end]})

    cancelled = fn ->
      assert {:error, :max_retries_exceeded, :boom} =
               TimeoutRetryWorker.execute(worker, always_fails(),
                 max_retries: retries,
                 base_delay_ms: 1,
                 max_delay_ms: 1,
                 attempt_timeout_ms: 1_000
               )
    end

    zeroed = fn ->
      assert {:error, :max_retries_exceeded, :boom} =
               TimeoutRetryWorker.execute(worker, always_fails(),
                 max_retries: retries,
                 base_delay_ms: 0,
                 max_delay_ms: 0,
                 attempt_timeout_ms: 1_000
               )
    end

    baseline_ms = elapsed_ms(cancelled)
    zero_delay_ms = elapsed_ms(zeroed)

    # A 1 ms wait per retry would add ~400 ms over the zero-wait baseline.
    assert zero_delay_ms - baseline_ms < 200
  end