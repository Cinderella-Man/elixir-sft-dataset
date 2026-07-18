  @doc "Builds with factory defaults and persists via `MyApp.Repo`."
  @spec insert(atom()) :: struct()
  def insert(name), do: insert(name, [], [])

  @doc "Builds from `opts` (overrides or traits) and persists."
  @spec insert(atom(), keyword() | [atom()]) :: struct()
  def insert(name, opts) when is_list(opts) do
    {traits, overrides} = split_opts(opts)
    insert(name, traits, overrides)
  end

  @doc "Builds with `traits` then `overrides`, then persists."
  @spec insert(atom(), [atom()], keyword()) :: struct()
  def insert(name, traits, overrides) when is_list(traits) and is_list(overrides) do
    name
    |> build(traits, overrides)
    |> MyApp.Repo.insert!()
  end