  test "steal_batch: 1 takes one item at a time from the back of the victim" do
    test_pid = self()
    items = [:block, 1, 2, 3, 4, :gate, 5, 6, 7, 8]

    task =
      Task.async(fn ->
        WorkStealQueue.run(
          items,
          2,
          fn
            :block ->
              send(test_pid, {:blocked, self()})

              receive do
                :release -> :released
              end

            :gate ->
              send(test_pid, {:gated, self()})

              receive do
                :go -> :went
              end

            x ->
              send(test_pid, {:processed, x})
              x
          end,
          steal_batch: 1
        )
      end)

    assert_receive {:gated, gate_pid}, 2_000
    assert_receive {:blocked, block_pid}, 2_000
    send(gate_pid, :go)

    seq =
      for _ <- 1..8 do
        assert_receive {:processed, x}, 2_000
        x
      end

    # victim holds [1, 2, 3, 4]; single-item steals must come off the back
    assert seq == [5, 6, 7, 8, 4, 3, 2, 1]

    send(block_pid, :release)
    %{results: results, metrics: metrics} = Task.await(task, 5_000)

    assert length(results) == 10
    assert metrics.steals == %{0 => 0, 1 => 4}
    assert metrics.stolen == %{0 => 0, 1 => 4}
  end