  defp validate_compare_fields(nil), do: nil

  defp validate_compare_fields(fields) when is_list(fields) do
    if Enum.all?(fields, &is_atom/1) do
      fields
    else
      raise ArgumentError,
            ":compare_fields must be a list of atoms, got: #{inspect(fields)}"
    end
  end

  defp validate_compare_fields(other) do
    raise ArgumentError, ":compare_fields must be a list of atoms, got: #{inspect(other)}"
  end