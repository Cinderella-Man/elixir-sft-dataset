  test "build/2 merges overrides into the struct" do
    user = Factory.build(:user, name: "Ada Lovelace", email: "ada@example.com")
    assert user.name == "Ada Lovelace"
    assert user.email == "ada@example.com"
  end