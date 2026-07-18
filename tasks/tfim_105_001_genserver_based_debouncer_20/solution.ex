  test "atom, binary and tuple keys of the same shape debounce independently" do
    Debouncer.call(:a, 30, notify(:atom_key_a))
    Debouncer.call("a", 30, notify(:string_key_a))
    Debouncer.call({:a, 1}, 30, notify(:tuple_key_a))

    # No key coalesces any other: all three funcs survive and run.
    assert_receive :atom_key_a, 400
    assert_receive :string_key_a, 400
    assert_receive :tuple_key_a, 400
  end