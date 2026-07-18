  test "a non-integer max_size is rejected at start-up" do
    assert %ArgumentError{} = start_error(name: unique_name(), max_size: 3.0)
    assert %ArgumentError{} = start_error(name: unique_name(), max_size: :three)
  end