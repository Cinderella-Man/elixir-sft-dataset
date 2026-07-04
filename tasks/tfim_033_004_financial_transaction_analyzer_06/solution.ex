  test "top_accounts contains at most 5 entries", %{report: r} do
    assert length(r.top_accounts) <= 5
  end