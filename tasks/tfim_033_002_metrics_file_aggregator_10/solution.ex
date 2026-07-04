  test "unique_tags only contains keys actually present", %{report: r} do
    assert Map.keys(r.unique_tags) |> Enum.sort() == ["host", "region"]
  end