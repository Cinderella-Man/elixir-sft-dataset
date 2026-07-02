  test "trailing edge coalesces to the last func after the delay" do
    EdgeDebouncer.call("k", 150, notify({:ran, 1}))
    EdgeDebouncer.call("k", 150, notify({:ran, 2}))
    EdgeDebouncer.call("k", 150, notify({:ran, 3}), edge: :trailing)

    assert_receive {:ran, 3}, 600
    refute_received {:ran, 1}
    refute_received {:ran, 2}
    refute_receive {:ran, _}, 250
  end