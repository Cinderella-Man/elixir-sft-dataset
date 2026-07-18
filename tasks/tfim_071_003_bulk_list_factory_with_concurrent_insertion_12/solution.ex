  test "insert_list of 0 returns an empty list" do
    before = length(FakeRepo.all())
    assert Factory.insert_list(0, :user) == []
    assert length(FakeRepo.all()) == before
  end