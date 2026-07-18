  defp to_existing_atom_safe(raw) when is_binary(raw) do
    String.to_existing_atom(raw)
  rescue
    ArgumentError -> nil
  end

  defp to_existing_atom_safe(_), do: nil