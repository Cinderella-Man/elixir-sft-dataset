  test "insert/2 persists with overrides" do
    user = Factory.insert(:user, name: "Ada")
    assert user.name == "Ada"
    assert is_integer(user.id)
  end