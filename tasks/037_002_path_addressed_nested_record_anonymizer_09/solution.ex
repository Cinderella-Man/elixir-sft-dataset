  defp safe_existing_atom(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> nil
  end