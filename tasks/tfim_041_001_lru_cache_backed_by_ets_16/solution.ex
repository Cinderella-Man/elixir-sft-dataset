  test "a negative max_size is rejected at start-up" do
    assert %ArgumentError{} = start_error(name: unique_name(), max_size: -1)
  end