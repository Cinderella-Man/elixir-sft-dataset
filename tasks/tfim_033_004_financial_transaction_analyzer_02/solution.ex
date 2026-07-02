  test "balance_by_account is correct", %{report: r} do
    # acct_1: +1000 - 250.50 + 300 = 1049.50
    # acct_2: +500 - 100 = 400.00
    # acct_3: +2000 - 750 = 1250.00
    assert_in_delta r.balance_by_account["acct_1"], 1049.50, 0.001
    assert_in_delta r.balance_by_account["acct_2"], 400.00, 0.001
    assert_in_delta r.balance_by_account["acct_3"], 1250.00, 0.001
  end