  test "insert/2 persists override values on success" do
    assert {:ok, user} = Factory.insert(:user, name: "Linus")
    assert user.name == "Linus"
  end