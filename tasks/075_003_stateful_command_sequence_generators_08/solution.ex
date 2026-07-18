  defp account_build(0, _bal, acc), do: SD.constant(Enum.reverse(acc))

  defp account_build(n, bal, acc) do
    SD.bind(account_command(bal), fn cmd ->
      account_build(n - 1, account_apply(bal, cmd), [cmd | acc])
    end)
  end