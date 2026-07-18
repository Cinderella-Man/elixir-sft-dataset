  @doc """
  Starts the runner.

  Accepts a `:name` option used for process registration so the process can be
  referred to by an atom name in the other functions.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end