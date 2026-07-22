  defp normalize_spec!(entries) when is_list(entries) do
    Enum.reduce(entries, %{}, fn entry, acc ->
      {table, table_deps} =
        case entry do
          t when is_binary(t) ->
            {t, []}

          {t, ds} when is_binary(t) and is_list(ds) ->
            {t, ds}

          other ->
            raise ArgumentError, "invalid table spec entry: #{inspect(other)}"
        end

      validate_identifier!(table)
      Enum.each(table_deps, &validate_identifier!/1)
      Map.put(acc, table, table_deps)
    end)
  end

  defp normalize_spec!(other) do
    raise ArgumentError, "expected :tables to be a list, got: #{inspect(other)}"
  end