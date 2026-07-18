  @impl true
  def init(opts) do
    state = %{
      max_bytes: Keyword.get(opts, :max_bytes, @default_max_bytes),
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      size_fn: Keyword.get(opts, :size_fn, @default_size_fn),
      on_flush: Keyword.get(opts, :on_flush, @default_on_flush),
      # Buffer stored in reverse push order for O(1) prepend; reversed into push
      # order right before being handed to the callback.
      buffer: [],
      weight: 0,
      timer: nil,
      timer_ref: nil
    }

    {:ok, state}
  end