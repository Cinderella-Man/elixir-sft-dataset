  defp update_transaction_count(acc, type) do
    Map.update!(acc, :transaction_count, fn counts ->
      Map.update(counts, type, 1, &(&1 + 1))
    end)
  end