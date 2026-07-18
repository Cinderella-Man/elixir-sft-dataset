  @doc """
  Starts the state-machine server.

  Options:

    * `:repo` (required) — a configured Ecto repo module.
    * `:pending_ttl_ms` (optional) — non-negative integer number of milliseconds
      after which a still-`:pending` entity is automatically expired. If omitted
      or `nil`, automatic expiry is disabled.
    * `:name` (optional) — a name under which to register the process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end