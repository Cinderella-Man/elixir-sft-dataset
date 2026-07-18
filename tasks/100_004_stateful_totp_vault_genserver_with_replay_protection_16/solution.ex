  @doc """
  Starts the vault server.

  Accepts the standard `:name` option for registering the process. Returns
  `{:ok, pid}` on success.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {gen_opts, _rest} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, %{}, gen_opts)
  end