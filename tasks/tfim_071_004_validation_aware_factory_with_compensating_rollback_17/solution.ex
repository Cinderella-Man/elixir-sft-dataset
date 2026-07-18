  test "valid? on a post does not leave stray association rows" do
    before = length(FakeRepo.all())
    assert Factory.valid?(:post)
    assert length(FakeRepo.all()) == before
  end