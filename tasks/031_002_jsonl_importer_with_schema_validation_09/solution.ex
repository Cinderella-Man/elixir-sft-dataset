  # Format checks only apply to string-typed fields holding a string value.
  defp format_errors(value, :string, format, name)
       when is_binary(value) and not is_nil(format) do
    check_format(String.trim(value), format, name)
  end

  defp format_errors(_value, _type, _format, _name), do: []