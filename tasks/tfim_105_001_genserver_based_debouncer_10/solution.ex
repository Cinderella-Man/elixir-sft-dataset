  test "call/3 returns :ok" do
    assert :ok = Debouncer.call("k", 100, notify(:x))
    assert_receive :x, 400
  end