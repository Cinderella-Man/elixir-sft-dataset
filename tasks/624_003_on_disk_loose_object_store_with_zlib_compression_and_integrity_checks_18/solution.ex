  @doc """
  Stores `content` and returns `{:ok, hash}`.

  The SHA-1 hash of `content` is computed, and the zlib-compressed bytes are
  written to the object's path on disk. The operation is idempotent: storing
  the same content twice yields the same hash and does not rewrite an
  existing file.
  """
  @spec store(server(), iodata()) :: {:ok, hash()} | {:error, term()}
  def store(server, content) do
    GenServer.call(server, {:store, IO.iodata_to_binary(content)})
  end