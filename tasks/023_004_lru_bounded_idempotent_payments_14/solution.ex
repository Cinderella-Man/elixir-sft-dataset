  @doc """
  Starts the server. Accepts `:max_keys` (a positive integer, default 1000) and
  `:clock` (a zero-arity ms clock). Raises `ArgumentError` when `:max_keys` is
  not a positive integer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    max_keys = Keyword.get(opts, :max_keys, @default_max_keys)

    unless is_integer(max_keys) and max_keys > 0 do
      raise ArgumentError, ":max_keys must be a positive integer"
    end

    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end