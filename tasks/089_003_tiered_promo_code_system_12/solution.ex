  defp ensure_unique(cs, state) do
    if Map.has_key?(state.codes, cs), do: {:error, :already_exists}, else: :ok
  end