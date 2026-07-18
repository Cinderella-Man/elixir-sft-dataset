  # Validates and returns :key_fields from opts, raising on bad input.
  defp fetch_key_fields!(opts) do
    case Keyword.fetch(opts, :key_fields) do
      {:ok, fields} when is_list(fields) and fields != [] ->
        unless Enum.all?(fields, &is_atom/1) do
          raise ArgumentError, ":key_fields must be a non-empty list of atoms"
        end

        fields

      {:ok, _} ->
        raise ArgumentError, ":key_fields must be a non-empty list of atoms"

      :error ->
        raise ArgumentError, "required option :key_fields is missing"
    end
  end