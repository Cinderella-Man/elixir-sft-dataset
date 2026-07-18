  test "a settled :both burst leaves no state and the next call fires leading again" do
    EdgeDebouncer.call("k", 100, notify({:b, 1}), edge: :both)
    EdgeDebouncer.call("k", 100, notify({:b, 2}), edge: :both)

    assert_receive {:b, 1}, 200
    # Trailing arriving means the burst has settled and the key is cleared.
    assert_receive {:b, 2}, 500

    EdgeDebouncer.call("k", 100, notify({:b, 3}), edge: :both)
    assert_receive {:b, 3}, 200
  end