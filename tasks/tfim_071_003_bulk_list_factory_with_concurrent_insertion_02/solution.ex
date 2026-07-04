  test "build/1 returns a struct without touching the DB" do
    before = length(FakeRepo.all())
    user = Factory.build(:user)
    assert is_binary(user.email) and user.email != ""
    assert length(FakeRepo.all()) == before
  end