  test "insert/2 persists the override values" do
    user = Factory.insert(:user, name: "Linus Torvalds")
    assert user.name == "Linus Torvalds"
    assert is_integer(user.id)
  end