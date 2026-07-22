  # With parsed headers and rows, run validation.
  defp process_parsed({_headers, []} = _parsed, _schema) do
    {:ok, [], []}
  end

  defp process_parsed({headers, rows}, schema) do
    header_count = length(headers)

    {valid_rows, error_report} =
      rows
      |> Enum.with_index(1)
      |> Enum.reduce({[], []}, fn {raw_row, row_num}, {valid_acc, err_acc} ->
        row_map = build_row_map(headers, raw_row, header_count)
        errors = validate_row(row_map, schema)

        case errors do
          [] ->
            # Keep only schema fields that are present in the CSV headers.
            filtered =
              schema
              |> Enum.filter(fn field -> field.name in headers end)
              |> Enum.map(fn field -> {field.name, Map.get(row_map, field.name, "")} end)
              |> Map.new()

            {[filtered | valid_acc], err_acc}

          _ ->
            tagged = Enum.map(errors, fn {field, msg} -> {row_num, field, msg} end)
            {valid_acc, err_acc ++ tagged}
        end
      end)

    {:ok, Enum.reverse(valid_rows), error_report}
  end