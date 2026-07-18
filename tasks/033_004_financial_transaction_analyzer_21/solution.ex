  defp build_report(acc) do
    %{
      balance_by_account: ensure_float_values(acc.balance_by_account),
      volume_by_currency: ensure_float_values(acc.volume_by_currency),
      transaction_count: acc.transaction_count,
      top_accounts: compute_top_accounts(acc.volume_by_account),
      daily_volume: ensure_float_values(acc.daily_volume),
      time_range: acc.timestamps,
      malformed_count: acc.malformed
    }
  end