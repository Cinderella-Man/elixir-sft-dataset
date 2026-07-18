  @doc """
  Starts the token server.

  Options:

    * `:secret` (required) — a binary HMAC signing key used for every token this
      server issues and redeems.
    * `:clock` (optional) — a zero-arity function returning a Unix epoch second.
      Defaults to reading `System.os_time(:second)`. This exists purely as a test
      seam for deterministic expiry testing.
    * `:name` (optional) — a name to register the server under.

  Returns `{:ok, pid}`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    secret = Keyword.fetch!(opts, :secret)

    if not is_binary(secret) do
      raise ArgumentError, ":secret must be a binary, got: #{inspect(secret)}"
    end

    clock = Keyword.get(opts, :clock, fn -> System.os_time(:second) end)

    if not is_function(clock, 0) do
      raise ArgumentError, ":clock must be a zero-arity function, got: #{inspect(clock)}"
    end

    server_opts =
      case Keyword.fetch(opts, :name) do
        {:ok, name} -> [name: name]
        :error -> []
      end

    GenServer.start_link(__MODULE__, {secret, clock}, server_opts)
  end