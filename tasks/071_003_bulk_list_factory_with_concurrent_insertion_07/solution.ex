  @doc "Returns a plain map of `name`'s fields (no struct, no `:id`)."
  @spec params_for(factory_name()) :: map()
  def params_for(name), do: params_for(name, [])

  @doc "Returns a plain map of `name`'s fields with `overrides`, minus `:id`."
  @spec params_for(factory_name(), overrides()) :: map()
  def params_for(name, overrides) do
    name
    |> build(overrides)
    |> Map.from_struct()
    |> Map.delete(:id)
  end