  defp accumulate(acc, entry) do
    signed_amount = if entry.type == "credit", do: entry.amount, else: -entry.amount

    acc
    |> update_balance(entry.account_id, signed_amount)
    |> update_volume_by_account(entry.account_id, entry.amount)
    |> update_volume_by_currency(entry.currency, entry.amount)
    |> update_transaction_count(entry.type)
    |> update_daily_volume(entry.timestamp, entry.amount)
    |> update_timestamps(entry.timestamp)
  end