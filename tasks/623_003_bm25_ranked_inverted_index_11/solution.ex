  @impl GenServer
  def init(opts) do
    state = %{
      stop_words: Keyword.get(opts, :stop_words, @default_stop_words),
      k1: Keyword.get(opts, :k1, 1.2),
      b: Keyword.get(opts, :b, 0.75),
      docs: %{},
      postings: %{}
    }

    {:ok, state}
  end