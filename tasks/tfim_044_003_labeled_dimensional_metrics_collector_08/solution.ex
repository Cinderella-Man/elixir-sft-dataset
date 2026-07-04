  test "get/1 returns nil when the name has no series" do
    assert Metrics.get(:unknown) == nil
  end