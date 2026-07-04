  test "timed-out tasks leave no zombie processes behind" do
    before_pids = MapSet.new(Process.list())

    sources =
      for i <- 1..10 do
        {i, slow_ok(i, 2_000)}
      end

    ConcurrentFetcher.fetch_all(sources, 100)

    # Give the VM a moment to finish any teardown
    Process.sleep(50)

    after_pids = MapSet.new(Process.list())
    new_pids = MapSet.difference(after_pids, before_pids)

    assert MapSet.size(new_pids) == 0,
           "Expected no leftover processes, found: #{inspect(MapSet.to_list(new_pids))}"
  end