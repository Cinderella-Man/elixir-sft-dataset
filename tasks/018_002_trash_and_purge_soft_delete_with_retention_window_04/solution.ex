  defp validate_fields(attrs, fields) do
    {values, errors} =
      Enum.reduce(fields, {%{}, %{}}, fn field, {vals, errs} ->
        val = get_field(attrs, field)

        if present?(val) do
          {Map.put(vals, field, val), errs}
        else
          {vals, Map.put(errs, field, ["can't be blank"])}
        end
      end)

    if errors == %{}, do: {:ok, values}, else: {:error, errors}
  end