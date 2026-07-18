  @doc """
  Appends `item` to `key`'s buffer, re-arms the `delay_ms` timer, and remembers
  `handler` (a 1-arity function). Returns `:ok` promptly.
  """
  @spec call(term(), non_neg_integer(), term(), (list() -> any())) :: :ok
  def call(key, delay_ms, item, handler)
      when is_integer(delay_ms) and delay_ms >= 0 and is_function(handler, 1) do
    GenServer.cast(__MODULE__, {:submit, key, delay_ms, item, handler})
  end