  test "top errors contains at most 10 entries", %{report: r} do
    assert length(r.top_errors) <= 10
  end