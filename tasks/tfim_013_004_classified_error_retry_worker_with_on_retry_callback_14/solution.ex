  test "max_delay_ms caps the computed delay", %{rw: _rw} do
    start_supervised!({Counter, 0})
    _timestamps = :ets.new(:ts_cap_v3, [:set, :public, :named_table])
    test_pid = self()

    func = fn ->
      attempt = Counter.increment_and_get()
      :ets.insert(:ts_cap_v3, {attempt, Clock.now()})
      send(test_pid, {:attempt_done, attempt})

      if attempt <= 5,
        do: {:error, :transient, :fail},
        else: {:ok, :done}
    end

    {:ok, rw2} =
      ClassifiedRetryWorker.start_link(clock: &Clock.now/0, random: &ZeroRandom.rand/1)

    task =
      Task.async(fn ->
        ClassifiedRetryWorker.execute(rw2, func,
          max_retries: 5,
          base_delay_ms: 1,
          max_delay_ms: 300
        )
      end)

    assert_receive {:attempt_done, 1}

    logical_delays = [100, 200, 300, 300, 300]

    for {delay, attempt_num} <- Enum.with_index(logical_delays, 2) do
      Clock.advance(delay)
      assert_receive {:attempt_done, ^attempt_num}
    end

    assert {:ok, :done} = Task.await(task, 5_000)

    [{1, t1}, {2, t2}, {3, t3}, {4, t4}, {5, t5}, {6, t6}] =
      for i <- 1..6, do: :ets.lookup(:ts_cap_v3, i) |> List.first()

    assert t2 - t1 == 100
    assert t3 - t2 == 200
    assert t4 - t3 == 300
    assert t5 - t4 == 300
    assert t6 - t5 == 300

    :ets.delete(:ts_cap_v3)
  end