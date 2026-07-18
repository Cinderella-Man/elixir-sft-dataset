  test "start_link registers under a :name and the api works through that name" do
    name = :interval_registry_promise_named
    {:ok, pid} = IntervalRegistry.start_link(name: name)
    assert Process.whereis(name) == pid

    {:ok, id} = IntervalRegistry.insert(name, {2, 6})
    assert IntervalRegistry.size(name) == 1
    assert [{2, 6}] = IntervalRegistry.overlapping(name, {6, 9})
    assert IntervalRegistry.stab_count(name, 4) == 1
    assert :ok = IntervalRegistry.remove(name, id)
    assert IntervalRegistry.size(name) == 0

    ref = Process.monitor(pid)
    assert :ok = IntervalRegistry.stop(name)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
  end