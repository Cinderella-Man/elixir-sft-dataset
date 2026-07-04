  test "insert_list/2 persists the requested count" do
    before = length(FakeRepo.all())
    users = Factory.insert_list(10, :user)
    assert length(users) == 10
    assert Enum.all?(users, &is_integer(&1.id))
    assert length(FakeRepo.all()) == before + 10
  end