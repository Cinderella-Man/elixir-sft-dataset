  test "user_id override on a failing post leaves no stray rows" do
    {:ok, existing} = Factory.insert(:user)
    before = length(FakeRepo.all())
    assert {:error, _} = Factory.insert(:post, user_id: existing.id, body: nil)
    assert length(FakeRepo.all()) == before
  end