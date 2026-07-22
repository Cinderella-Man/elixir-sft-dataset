  test "an idle worker steals from the BACK of a busy peer's queue" do
    test_pid = self()

    # Six items across two workers partition [1, 2, 3] / [4, 5, 6]. Worker 0
    # parks inside process_fn on item 1 (queue left: [2, 3]); worker 1 races
    # through its own queue and MUST steal — and the steal takes the BACK
    # half, so item 3 lands on worker 1 while item 2 stays with worker 0
    # (a single-item queue is never a victim).
    blocker = fn
      1 ->
        send(test_pid, {:blocked, self()})

        receive do
          :go -> :one
        end

      n ->
        n
    end

    task = Task.async(fn -> WorkStealQueue.run([1, 2, 3, 4, 5, 6], 2, blocker) end)

    assert_receive {:blocked, worker_zero}, 1_000
    # Give worker 1 time to drain its own queue and perform the steal.
    Process.sleep(150)
    send(worker_zero, :go)

    results = Task.await(task, 5_000)
    by_item = Map.new(results, fn %{item: item, worker_id: id} -> {item, id} end)

    assert by_item[1] == 0
    assert by_item[2] == 0
    assert by_item[3] == 1
    assert by_item[4] == 1
    assert by_item[5] == 1
    assert by_item[6] == 1
  end