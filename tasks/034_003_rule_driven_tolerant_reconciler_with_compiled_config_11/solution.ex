  defp compare_fields_or_error(fields) do
    if atoms?(fields), do: {:ok, fields}, else: {:error, :invalid_compare_fields}
  end