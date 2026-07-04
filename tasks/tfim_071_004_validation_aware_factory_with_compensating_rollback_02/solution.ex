  test "build/1 returns a struct with default fields" do
    user = Factory.build(:user)
    assert is_binary(user.name) and user.name != ""
    assert is_binary(user.email) and user.email != ""
  end