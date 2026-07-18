  @doc """
  Submits an item to the buffer for a specific key.
  The caller blocks until the batch is flushed.
  """
  @spec submit(
          GenServer.server(),
          term(),
          term(),
          (list() -> {:ok, term()} | {:error, term()}),
          keyword()
        ) :: {:ok, term()} | {:error, term()}
  def submit(server, key, item, flush_fn, opts \\ []) when is_function(flush_fn, 1) do
    max_batch_size = Keyword.get(opts, :max_batch_size, 10)
    GenServer.call(server, {:submit, key, item, flush_fn, max_batch_size}, :infinity)
  end