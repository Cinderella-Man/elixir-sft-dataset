  test "a cache hit is served while the cache process is suspended and answers no calls",
       %{cl: cl} do
    assert {:ok, :db_value} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1

    # Suspended: the process still runs, but any GenServer call queues forever.
    # A hit that round-trips through the server would therefore never return.
    :sys.suspend(cl)

    task =
      Task.async(fn ->
        CacheLayer.fetch(cl, :users, "u:1", fn -> :must_not_run end)
      end)

    try do
      assert {:ok, :db_value} = Task.await(task, 500)
    after
      :sys.resume(cl)
    end

    assert Tracker.count() == 1
  end