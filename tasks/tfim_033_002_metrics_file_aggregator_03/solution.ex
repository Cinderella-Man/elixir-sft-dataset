  test "per_metric stats for mem_usage are correct", %{report: r} do
    mem = r.per_metric["mem_usage"]
    assert mem.count == 2
    assert mem.min == 1024
    assert mem.max == 2048
    assert mem.sum == 3072
    assert_in_delta mem.mean, 1536.0, 0.001
  end