  @impl true
  def init(opts) do
    state = %{
      batch_size: Keyword.get(opts, :batch_size, @default_batch_size),
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      on_flush: Keyword.get(opts, :on_flush, @default_on_flush),
      # key => %{buffer, count, timer, timer_ref}
      keys: %{}
    }

    {:ok, state}
  end