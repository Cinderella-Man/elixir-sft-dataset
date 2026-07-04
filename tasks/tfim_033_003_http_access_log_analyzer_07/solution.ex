  test "max_duration picks the slowest request", %{report: r} do
    assert r.max_duration == {"/api/products", 250.0}
  end