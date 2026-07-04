  test "daily_volume is correct", %{report: r} do
    # 2024-01-15: 1000 + 250.50 + 500 + 100 + 300 + 2000 = 4150.50
    # 2024-01-16: 750
    assert_in_delta r.daily_volume[{2024, 1, 15}], 4150.50, 0.001
    assert_in_delta r.daily_volume[{2024, 1, 16}], 750.00, 0.001
  end