  @spec normalize_policy_key(term()) :: String.t()
  defp normalize_policy_key(key) when is_atom(key) do
    key |> Atom.to_string() |> String.downcase()
  end

  defp normalize_policy_key(key) when is_binary(key), do: String.downcase(key)

  defp normalize_policy_key(key) do
    raise ArgumentError, "policy key must be an atom or string, got: #{inspect(key)}"
  end