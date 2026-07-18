  @doc """
  Starts the feature-flag process.

  Options:

    * `:table_name` — name of the ETS table (default `#{inspect(@default_table)}`);
    * `:name` — process registration name; pass `nil` to skip registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    table_name = Keyword.get(opts, :table_name, @default_table)
    name = Keyword.get(opts, :name, @default_name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{table_name: table_name}, gen_opts)
  end