  @spec norm_key(term()) :: {:ok, String.t()} | :error
  defp norm_key(key) when is_atom(key) do
    {:ok, key |> Atom.to_string() |> String.downcase()}
  end

  defp norm_key(key) when is_binary(key), do: {:ok, String.downcase(key)}
  defp norm_key(_key), do: :error