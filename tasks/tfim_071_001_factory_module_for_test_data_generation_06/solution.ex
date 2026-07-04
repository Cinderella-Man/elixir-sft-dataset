  test "insert/1 returns a struct with an id" do
    user = Factory.insert(:user)
    assert is_integer(user.id) and user.id > 0
  end