  test "insert/2 with a trait persists the trait values" do
    user = Factory.insert(:user, [:admin])
    assert is_integer(user.id)
    assert user.role == "admin"
  end