  @doc """
  Return a previously checked-out connection to the pool. Always returns `:ok`.
  If a caller is blocked in `checkout/2`, the connection is handed directly to
  the longest-waiting one.
  """
  def checkin(name, conn) do
    GenServer.call(name, {:checkin, conn})
  end