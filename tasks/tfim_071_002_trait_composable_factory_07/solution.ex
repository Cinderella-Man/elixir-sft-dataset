  test "explicit overrides beat traits" do
    user = Factory.build(:user, [:admin], role: "superuser")
    assert user.role == "superuser"
  end