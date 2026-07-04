  test "traits beat factory defaults" do
    default = Factory.build(:user)
    assert default.role == "member"
    admin = Factory.build(:user, [:admin], [])
    assert admin.role == "admin"
  end