  # Process all non-blank lines and validate each against the schema.
  defp process_lines(lines, schema) do
    {valid_records, error_report} =
      lines
      |> Enum.with_index(1)
      |> Enum.reduce({[], []}, fn {line, line_num}, {valid_acc, err_acc} ->
        case Jason.decode(line) do
          {:ok, record} when is_map(record) ->
            errors = validate_record(record, schema)

            case errors do
              [] ->
                filtered = build_valid_record(record, schema)
                {[filtered | valid_acc], err_acc}

              _ ->
                tagged = Enum.map(errors, fn {field, msg} -> {line_num, field, msg} end)
                {valid_acc, err_acc ++ tagged}
            end

          {:ok, _not_a_map} ->
            {valid_acc, err_acc ++ [{line_num, "_line", "invalid JSON"}]}

          {:error, _} ->
            {valid_acc, err_acc ++ [{line_num, "_line", "invalid JSON"}]}
        end
      end)

    {:ok, Enum.reverse(valid_records), error_report}
  end