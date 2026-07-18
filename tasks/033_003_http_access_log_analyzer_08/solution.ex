  defp initial_acc do
    %{
      by_method: %{},
      by_status: %{},
      path_counts: %{},
      duration_sum: 0.0,
      max_duration: nil,
      timestamps: nil,
      requests_per_minute: %{},
      total: 0,
      error_count: 0,
      malformed: 0
    }
  end