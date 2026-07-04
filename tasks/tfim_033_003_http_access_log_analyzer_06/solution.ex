  test "avg_duration is correct", %{report: r} do
    # (12.5 + 15.0 + 45.3 + 8.2 + 3.1 + 250.0 + 22.0 + 1.5) / 8
    expected = (12.5 + 15.0 + 45.3 + 8.2 + 3.1 + 250.0 + 22.0 + 1.5) / 8
    assert_in_delta r.avg_duration, expected, 0.001
  end