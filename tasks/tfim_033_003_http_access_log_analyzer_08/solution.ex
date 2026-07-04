  test "error_rate counts status >= 400", %{report: r} do
    # 404 + 500 = 2 errors out of 8 valid lines
    assert_in_delta r.error_rate, 2 / 8, 0.0001
  end