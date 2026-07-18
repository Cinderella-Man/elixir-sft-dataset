  @doc """
  Starts the server.

  Supports the `:orphan_strategy` option (`:discard`, the default, or
  `:raise_to_root`), which governs how nodes referencing an absent parent are
  treated when the forest is computed.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    strategy = Keyword.get(opts, :orphan_strategy, :discard)
    GenServer.start_link(__MODULE__, strategy)
  end