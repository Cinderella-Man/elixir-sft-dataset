  test "build_list does not persist anything by itself" do
    before = length(FakeRepo.all())
    Factory.build_list(5, :user)
    assert length(FakeRepo.all()) == before
  end