  defp initial_acc do
    %{
      per_metric: %{},
      timestamps: nil,
      samples_per_hour: %{},
      unique_tags: %{},
      total: 0,
      malformed: 0
    }
  end