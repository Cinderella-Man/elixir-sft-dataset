  @doc """
  Borrow a connection, blocking up to `timeout` milliseconds if the pool is at
  capacity. Returns `{:ok, conn}` or `{:error, :timeout}`.
  """
  def checkout(name, timeout) when is_integer(timeout) and timeout >= 0 do
    # We never rely on GenServer.call's own timeout — the server always replies
    # within `timeout` ms on its own, so we wait :infinity on the call itself.
    GenServer.call(name, {:checkout, timeout}, :infinity)
  end