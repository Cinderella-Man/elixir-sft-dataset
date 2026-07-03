  # Validate a single field value against its field definition.
  defp validate_field(value, field) do
    required? = Map.get(field, :required, true)
    type = Map.get(field, :type, :string)
    format = Map.get(field, :format, nil)

    # Determine if value is "absent" for required checks.
    absent? = is_nil(value) or (is_binary(value) and String.trim(value) == "")

    required_errors =
      if required? and absent? do
        [{field.name, "is required"}]
      else
        []
      end

    # Type and format checks only apply to non-nil values.
    type_errors =
      if not is_nil(value) and not (is_binary(value) and String.trim(value) == "") do
        check_type(value, type, field.name)
      else
        []
      end

    format_errors =
      if not is_nil(value) and is_binary(value) and String.trim(value) != "" and format != nil do
        check_format(String.trim(value), format, field.name)
      else
        []
      end

    required_errors ++ type_errors ++ format_errors
  end