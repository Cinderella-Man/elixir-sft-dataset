  test "unknown trait raises ArgumentError" do
    assert_raise ArgumentError, fn -> Factory.build(:user, [:wizard], []) end
  end