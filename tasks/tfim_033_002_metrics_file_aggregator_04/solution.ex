  test "per_metric stats for disk_io are correct", %{report: r} do
    disk = r.per_metric["disk_io"]
    assert disk.count == 1
    assert disk.min == 500
    assert disk.max == 500
    assert disk.sum == 500
    assert_in_delta disk.mean, 500.0, 0.001
  end