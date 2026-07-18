  test "default jitter source keeps a one-millisecond delay at a one-millisecond wait" do
    retries = 300
    worker = start_supervised!({TimeoutRetryWorker, []})

    overhead = fn ->
      assert {:error, :max_retries_exceeded, :boom} =
               TimeoutRetryWorker.execute(worker, always_fails(),
                 max_retries: retries,
                 base_delay_ms: 0,
                 max_delay_ms: 0,
                 attempt_timeout_ms: 1_000
               )
    end

    jittered = fn ->
      assert {:error, :max_retries_exceeded, :boom} =
               TimeoutRetryWorker.execute(worker, always_fails(),
                 max_retries: retries,
                 base_delay_ms: 1,
                 max_delay_ms: 1,
                 attempt_timeout_ms: 1_000
               )
    end

    overhead_ms = elapsed_ms(overhead)
    waited_ms = elapsed_ms(jittered) - overhead_ms

    # 300 retries x exactly 1 ms of wait, minus the no-wait overhead baseline.
    assert waited_ms >= 100
    assert waited_ms <= 560
  end