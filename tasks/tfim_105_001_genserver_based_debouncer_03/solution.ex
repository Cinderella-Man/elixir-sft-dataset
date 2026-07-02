  test "executes the surviving func exactly once" do
    Debouncer.call("k", 100, notify(:once))

    assert_receive :once, 400
    refute_receive :once, 300
  end