  test "a fresh burst after settling fires leading again" do
    EdgeDebouncer.call("k", 100, notify(:first), edge: :leading)
    assert_receive :first, 100

    # Let the burst settle.
    Process.sleep(200)

    EdgeDebouncer.call("k", 100, notify(:second), edge: :leading)
    assert_receive :second, 100
  end