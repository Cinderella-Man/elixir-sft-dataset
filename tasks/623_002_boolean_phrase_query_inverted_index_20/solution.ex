  @doc """
  Starts the index process.

  Options:

    * `:name` — optional process name for registration.
    * `:stop_words` — optional `MapSet` of words to exclude during tokenization.
      Defaults to a built-in English stop-word set.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end