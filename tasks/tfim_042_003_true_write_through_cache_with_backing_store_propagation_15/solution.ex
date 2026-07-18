  test "terminate/2 runs during a supervised shutdown without crashing" do
    before_keys = MapSet.new(:persistent_term.get(), fn {key, _} -> key end)

    {:ok, sup} = Supervisor.start_link([{CacheLayer, []}], strategy: :one_for_one)
    [{_id, pid, _type, _mods}] = Supervisor.which_children(sup)

    assert {:ok, :v} = CacheLayer.fetch(pid, :sup_tbl, "k", fn -> :v end)
    # A repeat fetch is a cache hit; the raising loader proves it never runs.
    boom = fn -> raise "loader must not run on a cache hit" end
    assert {:ok, :v} = CacheLayer.fetch(pid, :sup_tbl, "k", boom)

    alive_keys = MapSet.new(:persistent_term.get(), fn {key, _} -> key end)
    created = MapSet.difference(alive_keys, before_keys)

    ref = Process.monitor(pid)
    :ok = Supervisor.stop(sup)

    # The child must have exited normally (a raising terminate/2 would surface
    # here as an abnormal exit reason), and its registrations must be gone.
    assert_receive {:DOWN, ^ref, :process, ^pid, reason}
    assert reason in [:normal, :shutdown]

    remaining = MapSet.new(:persistent_term.get(), fn {key, _} -> key end)
    assert MapSet.disjoint?(created, remaining)
  end