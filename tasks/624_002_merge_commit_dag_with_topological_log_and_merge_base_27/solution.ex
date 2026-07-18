  @doc """
  Stores `content`, returning `{:ok, hash}`.

  The hash is the lowercase hexadecimal SHA-1 digest of `content`. Storing the
  same content again returns the same hash without duplicating data.
  """
  @spec store(server(), binary()) :: {:ok, hash()}
  def store(server, content) when is_binary(content) do
    GenServer.call(server, {:store, content})
  end