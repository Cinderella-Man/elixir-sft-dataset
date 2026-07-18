  @doc """
  Start the storage process.

  Options:

    * `:root_dir` — base directory for all storage (default
      `#{inspect(@default_root)}`).
    * `:name` — optional name for process registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end