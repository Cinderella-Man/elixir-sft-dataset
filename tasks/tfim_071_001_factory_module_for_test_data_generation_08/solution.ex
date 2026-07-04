  test "insert/1 actually adds a record to the repo" do
    before_count = length(FakeRepo.all())
    Factory.insert(:user)
    assert length(FakeRepo.all()) == before_count + 1
  end