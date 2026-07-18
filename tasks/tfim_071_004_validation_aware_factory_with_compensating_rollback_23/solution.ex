  test "insert!(:post) raising on validation failure still rolls back the auto-created user" do
    before = length(FakeRepo.all())
    assert_raise ArgumentError, fn -> Factory.insert!(:post, body: nil) end
    assert length(FakeRepo.all()) == before
  end