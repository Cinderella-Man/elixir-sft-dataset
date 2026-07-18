  defp validate_compare_fields(opts) do
    case Keyword.fetch(opts, :compare_fields) do
      :error -> {:ok, nil}
      {:ok, nil} -> {:ok, nil}
      {:ok, fields} when is_list(fields) -> compare_fields_or_error(fields)
      {:ok, _other} -> {:error, :invalid_compare_fields}
    end
  end