  test "all returns a map of name => total count" do
    Metrics.observe(:a, 1)
    Metrics.observe(:a, 2)
    Metrics.observe(:b, 900)
    result = Metrics.all()
    assert result[:a] == 2
    assert result[:b] == 1
  end