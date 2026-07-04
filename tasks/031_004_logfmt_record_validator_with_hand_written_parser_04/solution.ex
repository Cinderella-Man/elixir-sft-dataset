  defp process_lines(lines, schema) do
    {valid_records, error_report} =
      lines
      |> Enum.with_index(1)
      |> Enum.reduce({[], []}, fn {line, line_num}, {valid_acc, err_acc} ->
        case parse_logfmt_line(line) do
          {:ok, record} ->
            errors = validate_record(record, schema)

            case errors do
              [] ->
                filtered = build_valid_record(record, schema)
                {[filtered | valid_acc], err_acc}

              _ ->
                tagged = Enum.map(errors, fn {field, msg} -> {line_num, field, msg} end)
                {valid_acc, err_acc ++ tagged}
            end

          {:error, :malformed} ->
            {valid_acc, err_acc ++ [{line_num, "_line", "malformed logfmt line"}]}
        end
      end)

    {:ok, Enum.reverse(valid_records), error_report}
  end