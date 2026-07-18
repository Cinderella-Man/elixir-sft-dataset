  test "a max-wait fire runs the newest func, not the one that opened the burst" do
    # delay=150, max=200. Second call at ~t=100 leaves 100ms of max window, so
    # fire_in = min(150, 100) = 100 and the fire at ~t=200 is the max-wait one.
    MaxWaitDebouncer.call("k", 150, 200, notify({:ran, 1}))
    refute_receive {:ran, _}, 100
    MaxWaitDebouncer.call("k", 150, 200, notify({:ran, 2}))

    assert_receive {:ran, 2}, 250
    refute_received {:ran, 1}
  end