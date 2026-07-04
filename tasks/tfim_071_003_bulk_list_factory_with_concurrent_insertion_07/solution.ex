  test "build_list of 0 returns an empty list" do
    assert Factory.build_list(0, :user) == []
  end