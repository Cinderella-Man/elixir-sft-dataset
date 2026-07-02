  test "error rate is errors / valid lines", %{report: r} do
    # 5 errors out of 9 valid lines
    assert_in_delta r.error_rate, 5 / 9, 0.0001
  end