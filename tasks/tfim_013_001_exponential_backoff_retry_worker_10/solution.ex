  test "jitter is added on top of the base delay", %{rw: _rw} do
    start_supervised!({Counter, 0})

    _timestamps = :ets.new(:ts_jitter, [:set, :public, :named_table])

    func = fn ->
      attempt = Counter.increment_and_get()
      :ets.insert(:ts_jitter, {attempt, Clock.now()})

      if attempt <= 1 do
        {:error, :fail}
      else
        {:ok, :done}
      end
    end

    # Jitter that always returns 50
    fixed_jitter = fn _max -> 50 end

    {:ok, rw2} =
      RetryWorker.start_link(
        clock: &Clock.now/0,
        random: fixed_jitter
      )

    task =
      Task.async(fn ->
        RetryWorker.execute(rw2, func,
          max_retries: 1,
          base_delay_ms: 100,
          max_delay_ms: 10_000
        )
      end)

    # Expected delay for retry 0: base=100 + jitter=50 = 150
    Process.sleep(50)
    Clock.advance(150)
    Process.sleep(50)

    assert {:ok, :done} = Task.await(task, 5_000)

    [{1, t1}] = :ets.lookup(:ts_jitter, 1)
    [{2, t2}] = :ets.lookup(:ts_jitter, 2)

    assert t2 - t1 == 150

    :ets.delete(:ts_jitter)
  end