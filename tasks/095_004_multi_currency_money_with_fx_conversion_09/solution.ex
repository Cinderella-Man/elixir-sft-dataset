  defp fetch_rate(rates, currency) do
    case Map.fetch(rates, currency) do
      {:ok, rate} when is_number(rate) -> rate
      _ -> raise ArgumentError, "no rate for currency #{inspect(currency)}"
    end
  end