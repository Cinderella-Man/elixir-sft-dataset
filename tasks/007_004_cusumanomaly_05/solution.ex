  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 5.0) * 1.0
    slack = Keyword.get(opts, :slack, 0.5) * 1.0
    warmup = Keyword.get(opts, :warmup_samples, 10)
    epsilon = Keyword.get(opts, :epsilon, 1.0e-6) * 1.0

    validate!(threshold, slack, warmup, epsilon)

    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end