  @doc """
  Starts the cache as a GenServer.

  Options:

    * `:name` – optional process registration name.
    * `:negative_hits` – a non-negative integer (default `3`) controlling how
      many times a cached failure is served before it is evicted and the
      fallback is retried. When `0`, failures are never cached.

  The started process owns the lifecycle of every ETS table it creates.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {neg, gen_opts} = Keyword.pop(opts, :negative_hits, 3)

    unless is_integer(neg) and neg >= 0 do
      raise ArgumentError,
            ":negative_hits must be a non-negative integer, got: #{inspect(neg)}"
    end

    GenServer.start_link(__MODULE__, %{negative_hits: neg}, gen_opts)
  end