  defp update_volume_by_currency(acc, currency, amount) do
    Map.update!(acc, :volume_by_currency, fn volumes ->
      Map.update(volumes, currency, amount, &(&1 + amount))
    end)
  end