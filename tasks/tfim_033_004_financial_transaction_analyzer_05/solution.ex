  test "top_accounts sorted by volume descending then alphabetically", %{report: r} do
    # acct_3: 2000 + 750 = 2750
    # acct_1: 1000 + 250.50 + 300 = 1550.50
    # acct_2: 500 + 100 = 600
    assert length(r.top_accounts) == 3

    [{id1, vol1}, {id2, vol2}, {id3, vol3}] = r.top_accounts
    assert id1 == "acct_3"
    assert_in_delta vol1, 2750.00, 0.001
    assert id2 == "acct_1"
    assert_in_delta vol2, 1550.50, 0.001
    assert id3 == "acct_2"
    assert_in_delta vol3, 600.00, 0.001
  end