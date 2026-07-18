  @doc """
  Starts the document store `GenServer`. Takes no required options.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts)