  @doc """
  Returns the number of keys currently retained by the counter.

  A key is retained only while it still holds at least one bucket. Once cleanup
  discards a key's last remaining bucket, the key is dropped entirely and no
  longer counted here. This exposes retained storage through the public API so
  callers can assert that memory does not leak.
  """
  @spec tracked_key_count(server()) :: non_neg_integer()
  def tracked_key_count(server) do
    GenServer.call(server, :tracked_key_count)
  end