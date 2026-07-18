  test "terminate/2 releases ETS tables the process owned" do
    Process.flag(:trap_exit, true)
    {:ok, cl} = CacheLayer.start_link([])
    Tracker.set({:ok, :v})

    assert {:ok, :v} = CacheLayer.fetch(cl, :items, "i:1", &Tracker.fallback/0)

    tid = :persistent_term.get({CacheLayer, cl, :items})
    refute :ets.info(tid) == :undefined

    :ok = GenServer.stop(cl)

    # After terminate/2 (and process death) the owned table is gone.
    assert :ets.info(tid) == :undefined
  end