  test "series is empty for an unknown name" do
    assert Metrics.series(:nope) == []
  end