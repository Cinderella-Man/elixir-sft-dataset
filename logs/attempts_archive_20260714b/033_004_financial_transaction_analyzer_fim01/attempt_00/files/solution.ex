  defp parse_line(trimmed) do
    with {:ok, obj} when is_map(obj) <- Jason.decode(trimmed),
         {:ok, ts_string} <- fetch_string(obj, "timestamp"),
         {:ok, account_id} <- fetch_nonempty_string(obj, "account_id"),
         {:ok, type} <- fetch_type(obj),
         {:ok, amount} <- fetch_positive_number(obj, "amount"),
         {:ok, currency} <- fetch_nonempty_string(obj, "currency"),
         {:ok, dt} <- parse_timestamp(ts_string) do
      {:ok,
       %{
         timestamp: dt,
         account_id: account_id,
         type: type,
         amount: amount,
         currency: currency
       }}
    else
      _ -> :error
    end
  end