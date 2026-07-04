  test "delays grow exponentially with zero jitter", %{rw: _rw} do
    start_supervised!({Counter, 0})
    _timestamps = :ets.new(:timestamps, [:set, :public, :named_table])

    # 1. Capture the test process PID to send signals back to it
    test_pid = self()

    func = fn ->
      attempt = Counter.increment_and_get()
      :ets.insert(:timestamps, {attempt, Clock.now()})

      # 2. Signal that this attempt is done
      send(test_pid, {:attempt_done, attempt})

      if attempt <= 4, do: {:error, :fail}, else: {:ok, :done}
    end

    {:ok, rw2} = RetryWorker.start_link(clock: &Clock.now/0, random: &ZeroRandom.rand/1)

    # 3. Use base_delay_ms: 1 so real-time passes instantly
    task =
      Task.async(fn ->
        RetryWorker.execute(rw2, func, max_retries: 4, base_delay_ms: 1)
      end)

    # 4. Step-through synchronization
    # Wait for Attempt 1
    assert_receive {:attempt_done, 1}

    # Advance clock, THEN wait for Attempt 2
    Clock.advance(100)
    assert_receive {:attempt_done, 2}

    Clock.advance(200)
    assert_receive {:attempt_done, 3}

    Clock.advance(400)
    assert_receive {:attempt_done, 4}

    Clock.advance(800)
    assert_receive {:attempt_done, 5}

    assert {:ok, :done} = Task.await(task)

    # Assertions will now pass because the timing is locked
    [{1, t1}, {2, t2}, {3, t3}, {4, t4}, {5, t5}] =
      for i <- 1..5, do: :ets.lookup(:timestamps, i) |> List.first()

    assert t2 - t1 == 100
    assert t3 - t2 == 200
    assert t4 - t3 == 400
    assert t5 - t4 == 800

    :ets.delete(:timestamps)
  end