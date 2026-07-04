  test "malformed count is correct", %{report: r} do
    # "not json!!!" + invalid type "transfer" = 2
    assert r.malformed_count == 2
  end