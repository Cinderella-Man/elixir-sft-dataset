  test "per_metric stats for cpu_usage are correct", %{report: r} do
    cpu = r.per_metric["cpu_usage"]
    assert cpu.count == 4
    assert_in_delta cpu.min, 23.1, 0.001
    assert_in_delta cpu.max, 90.0, 0.001
    assert_in_delta cpu.sum, 237.2, 0.001
    assert_in_delta cpu.mean, 237.2 / 4, 0.001
  end