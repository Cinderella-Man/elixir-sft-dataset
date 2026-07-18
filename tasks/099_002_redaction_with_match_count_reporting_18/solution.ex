  @spec key_string(term()) :: String.t() | nil
  defp key_string(key) when is_atom(key), do: key |> Atom.to_string() |> String.downcase()
  defp key_string(key) when is_binary(key), do: String.downcase(key)
  defp key_string(_key), do: nil