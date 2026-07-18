  defp initial_acc do
    %{
      counts_by_level: %{},
      error_messages: %{},
      timestamps: nil,
      errors_per_hour: %{},
      total: 0,
      malformed: 0
    }
  end