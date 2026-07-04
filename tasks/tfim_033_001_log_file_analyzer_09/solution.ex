  test "errors_per_hour only includes hours with at least one error", %{report: r} do
    refute Map.has_key?(r.errors_per_hour, {{2024, 1, 15}, 12})
  end