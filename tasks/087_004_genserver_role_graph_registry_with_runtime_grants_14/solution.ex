  @doc """
  Starts the `RoleRegistry` GenServer.

  Standard `GenServer` options such as `:name` are honored. The initial state
  has no roles, no inheritance edges, and no grants.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end