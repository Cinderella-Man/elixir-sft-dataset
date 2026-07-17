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

    # Type and format checks only apply to present, non-blank values.
    if absent? do
      required_errors
    else
      required_errors ++
        check_type(value, type, field.name) ++
        format_errors(value, type, format, field.name)
    end
  end