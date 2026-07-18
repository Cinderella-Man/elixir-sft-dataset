  @doc """
  Start the sanitizer server.

  Options:
    * `:name` — optional registered name.
    * `:max_filename_length` — integer, default `255`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end