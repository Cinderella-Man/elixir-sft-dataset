  @spec validate_key_fields!(term()) :: [atom(), ...]
  defp validate_key_fields!(fields) when is_list(fields) and fields != [] do
    if Enum.all?(fields, &is_atom/1) do
      fields
    else
      raise ArgumentError,
            ":key_fields must be a non-empty list of atoms, got: #{inspect(fields)}"
    end
  end

  defp validate_key_fields!(other) do
    raise ArgumentError, ":key_fields must be a non-empty list of atoms, got: #{inspect(other)}"
  end