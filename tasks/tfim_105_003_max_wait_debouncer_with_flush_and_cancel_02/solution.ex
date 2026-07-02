  test "coalesces to the last func after the delay when the burst settles" do
    MaxWaitDebouncer.call("k", 150, 1000, notify({:ran, 1}))
    MaxWaitDebouncer.call("k", 150, 1000, notify({:ran, 2}))
    MaxWaitDebouncer.call("k", 150, 1000, notify({:ran, 3}))

    assert_receive {:ran, 3}, 600
    refute_received {:ran, 1}
    refute_received {:ran, 2}
  end