  test "build_list/3 applies overrides to every element" do
    users = Factory.build_list(3, :user, name: "Same")
    assert Enum.all?(users, &(&1.name == "Same"))
  end