  test "malformed count is correct", %{report: r} do
    assert r.malformed_count == 2
  end