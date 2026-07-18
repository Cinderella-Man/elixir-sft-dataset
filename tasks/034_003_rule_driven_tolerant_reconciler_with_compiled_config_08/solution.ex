  defp validate_key_fields(opts) do
    case Keyword.fetch(opts, :key_fields) do
      :error -> {:error, :missing_key_fields}
      {:ok, [_ | _] = fields} -> if atoms?(fields), do: {:ok, fields}, else: key_error()
      {:ok, _other} -> key_error()
    end
  end