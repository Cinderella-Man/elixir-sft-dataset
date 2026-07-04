  test "multiple traits are applied left to right" do
    user = Factory.build(:user, [:admin, :inactive])
    assert user.role == "admin"
    assert user.active == false
  end