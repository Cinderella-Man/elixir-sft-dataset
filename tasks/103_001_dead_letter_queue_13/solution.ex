  @doc """
  Start the dead letter queue process.

  ## Options

    * `:clock` — a zero-arity function returning the current time in
      milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:name` — optional name for process registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    gen_opts =
      case name do
        nil -> []
        name -> [name: name]
      end

    GenServer.start_link(__MODULE__, opts, gen_opts)
  end