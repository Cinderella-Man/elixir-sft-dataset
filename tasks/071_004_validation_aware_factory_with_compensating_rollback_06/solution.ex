  @doc "Builds a struct for `name` (resolving/creating any associations)."
  @spec build(factory_name()) :: struct()
  def build(name), do: build(name, [])

  @doc "Builds a struct for `name`, merging `overrides`."
  @spec build(factory_name(), overrides()) :: struct()
  def build(name, overrides) do
    {struct, _assocs} = build_with_assocs(name, overrides)
    struct
  end