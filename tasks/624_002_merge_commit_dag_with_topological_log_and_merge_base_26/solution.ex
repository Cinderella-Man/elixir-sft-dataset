  @doc """
  Starts the object store process.

  Accepts a `:name` option for process registration; any other options are
  ignored. The internal state is an in-memory map of SHA-1 hex digest to the
  stored raw binary content.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    gen_opts =
      case Keyword.get(opts, :name) do
        nil -> []
        name -> [name: name]
      end

    GenServer.start_link(__MODULE__, %{}, gen_opts)
  end