  @doc """
  Start the object store process.

  Options:

    * `:name` — an optional name under which to register the process.
    * `:default_ttl_ms` — a positive integer number of milliseconds, or
      `:infinity` (the default), applied to any `put_object/5` that does not
      specify its own `:ttl_ms`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    default_ttl = Keyword.get(opts, :default_ttl_ms, :infinity)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{default_ttl_ms: default_ttl}, gen_opts)
  end