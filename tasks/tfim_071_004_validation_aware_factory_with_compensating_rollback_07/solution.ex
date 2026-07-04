  test "failed insert does not add any record" do
    before = length(FakeRepo.all())
    assert {:error, _} = Factory.insert(:user, email: nil)
    assert length(FakeRepo.all()) == before
  end