  @doc """
  Returns whether a built `name` (with `overrides`) is valid. Any association
  rows created during the check are rolled back so no stray rows remain.
  """
  @spec valid?(factory_name()) :: boolean()
  @spec valid?(factory_name(), overrides()) :: boolean()
  def valid?(name, overrides \\ []) do
    {struct, assocs} = build_with_assocs(name, overrides)
    Enum.each(assocs, &MyApp.Repo.delete!/1)
    validate(name, struct) == :ok
  end