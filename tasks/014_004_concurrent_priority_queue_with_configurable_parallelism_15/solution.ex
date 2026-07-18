  @doc """
  Starts the queue process.

  Options:

    * `:name` — optional name for process registration
    * `:processor` — single-arity function invoked for each task (default: `fn task -> task end`)
    * `:max_concurrency` — positive integer, maximum simultaneous tasks (default: `1`)

  Raises `ArgumentError` when `:max_concurrency` is not a positive integer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {processor, opts} = Keyword.pop(opts, :processor, fn task -> task end)
    {max_concurrency, opts} = Keyword.pop(opts, :max_concurrency, 1)
    {name, _opts} = Keyword.pop(opts, :name)

    if not (is_integer(max_concurrency) and max_concurrency > 0) do
      raise ArgumentError, ":max_concurrency must be a positive integer"
    end

    gen_opts = if name, do: [name: name], else: []

    GenServer.start_link(
      __MODULE__,
      %{processor: processor, max_concurrency: max_concurrency},
      gen_opts
    )
  end