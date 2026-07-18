  test "default steal batch takes half of the victim's remaining queue per steal" do
    test_pid = self()
    items = [:block, 1, 2, 3, 4, :gate, 5, 6, 7, 8]

    task =
      Task.async(fn ->
        WorkStealQueue.run(items, 2, fn
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
        end)
      end)

    # worker 0 owns [:block, 1, 2, 3, 4]; worker 1 owns [:gate, 5, 6, 7, 8].
    # Both park on their first item, so worker 0's remaining queue is [1, 2, 3, 4].
    assert_receive {:gated, gate_pid}, 2_000
    assert_receive {:blocked, block_pid}, 2_000
    send(gate_pid, :go)

    seq =
      for _ <- 1..8 do
        assert_receive {:processed, x}, 2_000
        x
      end

    # half of [1, 2, 3, 4] is 2 items, taken as one batch, then half of the rest
    assert seq == [5, 6, 7, 8, 3, 4, 2, 1]

    send(block_pid, :release)
    %{results: results, metrics: metrics} = Task.await(task, 5_000)

    assert length(results) == 10
    assert metrics.processed == %{0 => 1, 1 => 9}
    assert metrics.steals == %{0 => 0, 1 => 3}
    assert metrics.stolen == %{0 => 0, 1 => 4}
  end