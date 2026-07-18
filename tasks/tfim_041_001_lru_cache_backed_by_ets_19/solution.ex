  test "a missing name is a KeyError-style start-up failure" do
    assert %KeyError{} = start_error(max_size: 3)
  end