  test "insert!/1 returns the struct on success" do
    user = Factory.insert!(:user)
    assert is_integer(user.id)
  end