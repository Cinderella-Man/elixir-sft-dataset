  @doc """
  Starts the `MovingAverage` server.

  ## Options

    * `:name` – optional registration name passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end