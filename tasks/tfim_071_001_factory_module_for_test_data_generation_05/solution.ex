  test "build/2 only overrides specified fields, leaves others as defaults" do
    user = Factory.build(:user, name: "Grace Hopper")
    assert user.name == "Grace Hopper"
    assert is_binary(user.email) and user.email != ""
  end