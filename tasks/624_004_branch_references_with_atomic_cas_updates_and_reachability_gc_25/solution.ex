  @doc """
  Stores raw `content`, returning `{:ok, hash}` where `hash` is its SHA-1 hex
  digest. Idempotent: identical content always yields the same hash and is not
  duplicated.
  """
  @spec store(GenServer.server(), binary()) :: {:ok, hash}
  def store(server, content) when is_binary(content) do
    GenServer.call(server, {:store, content})
  end