  test "fresh counter has value 0", %{c: c} do
    assert Counter.value(c) == 0
  end