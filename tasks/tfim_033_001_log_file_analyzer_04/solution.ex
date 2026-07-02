  test "malformed count is correct", %{report: r} do
    # "not json at all!!!" + line missing required fields = 2
    assert r.malformed_count == 2
  end