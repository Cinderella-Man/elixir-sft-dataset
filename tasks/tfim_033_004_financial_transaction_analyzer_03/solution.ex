  test "volume_by_currency is correct", %{report: r} do
    # USD: 1000 + 250.50 + 300 = 1550.50
    # EUR: 500 + 100 = 600.00
    # GBP: 2000 + 750 = 2750.00
    assert_in_delta r.volume_by_currency["USD"], 1550.50, 0.001
    assert_in_delta r.volume_by_currency["EUR"], 600.00, 0.001
    assert_in_delta r.volume_by_currency["GBP"], 2750.00, 0.001
  end