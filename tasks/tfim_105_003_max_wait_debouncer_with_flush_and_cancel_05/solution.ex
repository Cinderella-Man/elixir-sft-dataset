  test "single call within max simply obeys the normal delay" do
    MaxWaitDebouncer.call("k", 100, 1000, notify(:one))
    assert_receive :one, 400
    refute_receive :one, 200
  end