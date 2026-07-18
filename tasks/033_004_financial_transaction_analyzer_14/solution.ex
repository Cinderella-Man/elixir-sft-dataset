  defp update_balance(acc, account_id, signed_amount) do
    Map.update!(acc, :balance_by_account, fn balances ->
      Map.update(balances, account_id, signed_amount, &(&1 + signed_amount))
    end)
  end