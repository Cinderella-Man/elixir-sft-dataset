  test "failed insert(:post) rolls back the auto-created user" do
    before = length(FakeRepo.all())
    assert {:error, {:missing_fields, fields}} = Factory.insert(:post, title: nil)
    assert :title in fields
    # The user auto-created for the association must be deleted again.
    assert length(FakeRepo.all()) == before
  end