  test "build/1 does not touch the database" do
    before = length(FakeRepo.all())
    Factory.build(:user)
    assert length(FakeRepo.all()) == before
  end