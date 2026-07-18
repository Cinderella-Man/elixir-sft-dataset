  @doc """
  Starts the TwoPhaseSet process.

  ## Options

    * `:name` — optional name for process registration.

  ## Examples

      {:ok, pid} = TwoPhaseSet.start_link([])
      {:ok, _}   = TwoPhaseSet.start_link(name: MySet)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name_opts, _rest} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, :ok, name_opts)
  end