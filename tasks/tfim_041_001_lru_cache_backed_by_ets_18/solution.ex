  test "a missing max_size is a KeyError-style start-up failure" do
    assert %KeyError{} = start_error(name: unique_name())
  end