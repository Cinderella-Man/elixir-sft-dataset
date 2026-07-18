  # Returns the set of field name *strings* declared on the schema, excluding
  # virtual fields.  We compare against strings (not atoms) because that is
  # what Jason gives us, avoiding the need for String.to_atom/1 on arbitrary
  # untrusted input.
  @spec schema_field_set(schema()) :: MapSet.t(String.t())
  defp schema_field_set(schema) do
    schema.__schema__(:fields)
    |> Enum.map(&Atom.to_string/1)
    |> MapSet.new()
  end