  test "transaction_count is correct", %{report: r} do
    assert r.transaction_count == %{"credit" => 4, "debit" => 3}
  end