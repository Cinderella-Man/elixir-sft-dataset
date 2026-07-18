  test "empty layer list raises ArgumentError" do
    assert_raise ArgumentError, fn -> LayeredConfig.merge([]) end
  end