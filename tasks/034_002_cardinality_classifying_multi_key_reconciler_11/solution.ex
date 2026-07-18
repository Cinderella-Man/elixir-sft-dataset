  defp validate_key_fields(key_fields)
       when is_list(key_fields) and key_fields != [] do
    if Enum.all?(key_fields, &is_atom/1) do
      key_fields
    else
      raise ArgumentError,
            ":key_fields must be a non-empty list of atoms, got: #{inspect(key_fields)}"
    end
  end

  defp validate_key_fields(other) do
    raise ArgumentError,
          ":key_fields must be a non-empty list of atoms, got: #{inspect(other)}"
  end