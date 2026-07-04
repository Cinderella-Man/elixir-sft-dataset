  test "build/2 with a trait list applies traits" do
    user = Factory.build(:user, [:admin])
    assert user.role == "admin"
    assert user.active == true
  end