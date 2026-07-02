  test "build/1 does not insert into the database" do
    before_count = length(FakeRepo.all())
    Factory.build(:user)
    assert length(FakeRepo.all()) == before_count
  end