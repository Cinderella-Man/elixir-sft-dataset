  test "all/0 and snapshot/0 return an empty map when nothing has been recorded" do
    assert Metrics.all() == %{}
    assert Metrics.snapshot() == %{}
  end