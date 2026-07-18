  test "keys can be arbitrary terms" do
    Debouncer.call({:user, 1}, 100, notify(:tuple_key))
    Debouncer.call(:atom_key, 100, notify(:atom_key_ran))

    assert_receive :tuple_key, 400
    assert_receive :atom_key_ran, 400
  end