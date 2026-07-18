  defp account_apply(bal, {:deposit, a}), do: bal + a
  defp account_apply(bal, {:withdraw, a}), do: bal - a