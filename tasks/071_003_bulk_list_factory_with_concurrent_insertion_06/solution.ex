  @doc "Builds a list of `count` structs for `name`."
  @spec build_list(non_neg_integer(), factory_name()) :: [struct()]
  def build_list(count, name), do: build_list(count, name, [])

  @doc "Builds a list of `count` structs for `name`, each with `overrides`."
  @spec build_list(non_neg_integer(), factory_name(), overrides()) :: [struct()]
  def build_list(count, name, overrides) when is_integer(count) and count >= 0 do
    Enum.map(1..count//1, fn _ -> build(name, overrides) end)
  end