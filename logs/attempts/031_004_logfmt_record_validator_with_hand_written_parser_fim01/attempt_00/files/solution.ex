  defp validate_field(value, field) do
    required? = Map.get(field, :required, true)
    type = Map.get(field, :type, :string)
    format = Map.get(field, :format, nil)

    # nil means key was missing; "" means key was present but empty
    absent? = is_nil(value) or value == ""

    required_errors =
      if required? and absent? do
        [{field.name, "is required"}]
      else
        []
      end

    # Type and format checks only apply to non-empty values.
    type_errors =
      if not absent? do
        check_type(value, type, field.name)
      else
        []
      end

    format_errors =
      if not absent? and format != nil do
        check_format(value, format, field.name)
      else
        []
      end

    required_errors ++ type_errors ++ format_errors
  end