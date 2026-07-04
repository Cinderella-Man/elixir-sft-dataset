  test "insert/3 applies traits then overrides then persists" do
    user = Factory.insert(:user, [:admin, :inactive], name: "Root")
    assert user.name == "Root"
    assert user.role == "admin"
    assert user.active == false
    assert is_integer(user.id)
  end