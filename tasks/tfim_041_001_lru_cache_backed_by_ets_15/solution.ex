  test "a max_size of zero is rejected at start-up" do
    assert %ArgumentError{} = start_error(name: unique_name(), max_size: 0)
  end