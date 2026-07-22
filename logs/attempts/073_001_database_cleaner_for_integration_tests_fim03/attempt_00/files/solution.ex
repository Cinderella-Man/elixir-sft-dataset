  defp validate_tables!(tables) when is_list(tables) do
    Enum.each(tables, fn
      table when is_binary(table) ->
        unless Regex.match?(@valid_identifier, table) do
          raise ArgumentError,
                "invalid table name #{inspect(table)}. " <>
                  "Table names must match /[a-zA-Z_][a-zA-Z0-9_]*/"
        end

      other ->
        raise ArgumentError,
              "expected table names to be strings, got: #{inspect(other)}"
    end)
  end

  defp validate_tables!(other) do
    raise ArgumentError, "expected :tables to be a list, got: #{inspect(other)}"
  end