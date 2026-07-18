  @doc """
  Start and (optionally) register the pool process.

  Options:

    * `:name`     — atom to register the process under.
    * `:max_size` — maximum connections ever alive at once (default `10`).
    * `:min_size` — connections created eagerly at startup (default `0`).
    * `:create`   — zero-arity fun returning a new, distinct connection
      (default `fn -> make_ref() end`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end