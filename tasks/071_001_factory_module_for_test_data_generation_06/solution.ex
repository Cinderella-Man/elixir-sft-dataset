  @doc "Builds and persists a struct for `factory_name` via `MyApp.Repo`."
  @spec insert(atom()) :: struct()
  def insert(factory_name), do: insert(factory_name, [])

  @doc "Builds with `overrides`, then persists via `MyApp.Repo`."
  @spec insert(atom(), Keyword.t()) :: struct()
  def insert(factory_name, overrides) do
    factory_name
    |> build(overrides)
    |> MyApp.Repo.insert!()
  end