  test "unknown trait raises through the inferred two-arity trait form" do
    assert_raise ArgumentError, fn -> Factory.build(:post, [:featured]) end
    assert_raise ArgumentError, fn -> Factory.insert(:user, [:wizard]) end
  end