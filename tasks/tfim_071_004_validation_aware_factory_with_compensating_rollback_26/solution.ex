  test "build/2 merges plain field overrides without persisting anything" do
    before = length(FakeRepo.all())
    user = Factory.build(:user, name: "Ada", email: "ada@example.com")
    assert %MyApp.User{name: "Ada", email: "ada@example.com"} = user
    assert length(FakeRepo.all()) == before
  end