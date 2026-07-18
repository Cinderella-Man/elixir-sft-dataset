  @doc """
  Starts the LWWSet process.

  ## Options

    * `:name` — optional name for process registration, passed directly to
      `GenServer.start_link/3`. Accepts any valid `GenServer` name term
      (atom, `{:global, term}`, `{:via, module, term}`, etc.).

  ## Examples

      # Anonymous process
      {:ok, pid} = LWWSet.start_link([])

      # Named process
      {:ok, _} = LWWSet.start_link(name: MySet)
      LWWSet.members(MySet)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name_opts, _rest} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, :ok, name_opts)
  end