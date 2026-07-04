  test "insert/1 actually adds a record on success" do
    before = length(FakeRepo.all())
    assert {:ok, _} = Factory.insert(:user)
    assert length(FakeRepo.all()) == before + 1
  end