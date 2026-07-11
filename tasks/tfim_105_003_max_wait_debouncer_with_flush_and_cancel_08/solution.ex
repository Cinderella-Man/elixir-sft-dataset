  test "cancel discards the pending func" do
    MaxWaitDebouncer.call("k", 200, 1000, notify(:cancelled))
    assert :ok = MaxWaitDebouncer.cancel("k")

    refute_receive :cancelled, 400
  end