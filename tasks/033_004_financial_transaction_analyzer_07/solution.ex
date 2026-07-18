  defp initial_acc do
    %{
      balance_by_account: %{},
      volume_by_account: %{},
      volume_by_currency: %{},
      transaction_count: %{},
      daily_volume: %{},
      timestamps: nil,
      malformed: 0
    }
  end