def from_schema(schema) do
  case schema do
    :integer ->
      SD.integer()

    {:integer, min, max}
    when is_integer(min) and is_integer(max) and min <= max ->
      SD.integer(min..max)

    :boolean ->
      SD.boolean()

    :string ->
      SD.string(:alphanumeric)

    {:string, min_len, max_len}
    when is_integer(min_len) and is_integer(max_len) and min_len >= 0 and min_len <= max_len ->
      SD.string(:alphanumeric, min_length: min_len, max_length: max_len)

    {:enum, values} when is_list(values) and values != [] ->
      SD.member_of(values)

    {:list, inner} ->
      SD.list_of(from_schema(inner))

    {:list, inner, opts} when is_list(opts) ->
      min = Keyword.get(opts, :min, 0)
      max = Keyword.get(opts, :max, 10)

      SD.bind(SD.integer(min..max), fn len ->
        SD.list_of(from_schema(inner), length: len)
      end)

    {:map, schema_map} when is_map(schema_map) ->
      generators = Map.new(schema_map, fn {key, value_schema} -> {key, from_schema(value_schema)} end)
      SD.fixed_map(generators)

    {:optional, inner} ->
      SD.one_of([SD.constant(nil), from_schema(inner)])

    {:one_of, schemas} when is_list(schemas) and schemas != [] ->
      SD.one_of(Enum.map(schemas, &from_schema/1))
  end
end