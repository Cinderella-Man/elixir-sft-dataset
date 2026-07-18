  @doc """
  Starts the masking server.

  `opts` is a keyword list. `opts[:sensitive_keys]` is a list of atoms and/or
  strings (defaulting to `[]`); key comparison during masking is
  case-insensitive and works for both atom and string keys.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end