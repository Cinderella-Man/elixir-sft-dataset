  @doc """
  Starts the promo-code process.

  Options:

    * `:clock` — a zero-arity function returning the current UTC `DateTime`.
      Defaults to `fn -> DateTime.utc_now() end`.
    * `:name` — the name to register the process under. Defaults to
      `#{inspect(__MODULE__)}`.
  """
  def start_link(opts \\ []) do
    clock = Keyword.get(opts, :clock, fn -> DateTime.utc_now() end)
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{clock: clock}, name: name)
  end