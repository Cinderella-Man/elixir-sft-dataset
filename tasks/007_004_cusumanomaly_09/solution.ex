  @impl GenServer
  def init(opts) do
    threshold = Keyword.get(opts, :threshold, 5.0) * 1.0
    slack = Keyword.get(opts, :slack, 0.5) * 1.0
    warmup = Keyword.get(opts, :warmup_samples, 10)
    epsilon = Keyword.get(opts, :epsilon, 1.0e-6) * 1.0

    {:ok,
     %{
       streams: %{},
       threshold: threshold,
       slack: slack,
       warmup_samples: warmup,
       epsilon: epsilon
     }}
  end