  defp update_volume_by_account(acc, account_id, amount) do
    Map.update!(acc, :volume_by_account, fn volumes ->
      Map.update(volumes, account_id, amount, &(&1 + amount))
    end)
  end