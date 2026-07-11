  test "a call after the previous one fired triggers a fresh execution" do
    Debouncer.call("k", 100, notify(:first))
    assert_receive :first, 400

    Debouncer.call("k", 100, notify(:second))
    assert_receive :second, 400
  end