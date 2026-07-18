  defp parse_sort(%{"sort" => raw}) do
    field = to_existing_atom_safe(raw)
    if field in @sortable, do: {:ok, field}, else: {:error, :invalid_sort_field}
  end

  defp parse_sort(_), do: {:ok, :id}