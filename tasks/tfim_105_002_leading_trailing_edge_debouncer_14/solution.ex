  test "the opening call's edge wins over a later call's edge option" do
    EdgeDebouncer.call("k", 150, notify(:lead), edge: :leading)
    EdgeDebouncer.call("k", 150, notify(:tail), edge: :trailing)

    # The burst was opened as :leading, so the first func fires immediately...
    assert_receive :lead, 200
    # ...and no trailing execution occurs even though a later call said :trailing.
    refute_receive :tail, 500
  end