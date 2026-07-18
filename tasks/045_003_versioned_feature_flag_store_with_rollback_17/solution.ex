  @doc """
  Starts the feature-flag server.

  Options:

  - `:table_name` — name of the primary ETS table (default `#{@default_table}`).
  - `:name` — process registration name (default `#{inspect(@default_name)}`);
    pass `nil` to skip registration.

  A second `:ordered_set` history table named `"<table_name>_history"` is also
  created and owned by the process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    table_name = Keyword.get(opts, :table_name, @default_table)
    name = Keyword.get(opts, :name, @default_name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{table_name: table_name}, gen_opts)
  end