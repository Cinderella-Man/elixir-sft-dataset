  test "with more items than workers, all workers are used" do
    results = WorkStealQueue.run(Enum.to_list(1..50), 4, fn x -> x end)

    # With 50 items split across 4 workers, every worker should get at
    # least some items before stealing even begins.
    assert length(worker_ids(results)) == 4
  end