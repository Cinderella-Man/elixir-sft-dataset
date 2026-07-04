  test "build/2 with a keyword list applies overrides" do
    user = Factory.build(:user, name: "Ada Lovelace", email: "ada@example.com")
    assert user.name == "Ada Lovelace"
    assert user.email == "ada@example.com"
    assert user.role == "member"
  end