  @spec strip_leading_space(String.t()) :: String.t()
  defp strip_leading_space(" " <> rest), do: rest
  defp strip_leading_space(account), do: account