  @doc """
  Starts the server. `opts` must include `:capacity` (positive integer) and
  may include `:name` for registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {capacity, opts} = Keyword.pop(opts, :capacity)
    GenServer.start_link(__MODULE__, capacity, opts)
  end