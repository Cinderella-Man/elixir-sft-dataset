  @doc """
  Start a `FuzzyIndex` process.

  Options:

    * `:name` — register the process under the given name.
    * `:stop_words` — a `MapSet` of words to exclude during tokenization. When omitted,
      the built-in default stop-word set is used.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end