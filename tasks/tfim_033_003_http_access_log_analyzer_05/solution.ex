  test "top_paths contains at most 10 entries", %{report: r} do
    assert length(r.top_paths) <= 10
  end