  @doc """
  Returns the raw internal state of the set.

  The returned map has the form:

      %{
        adds:    %{element => latest_add_timestamp, ...},
        removes: %{element => latest_remove_timestamp, ...}
      }

  This value can be sent to a remote node and passed to `LWWSet.merge/2`
  to synchronise state.
  """
  @spec state(server()) :: lww_state()
  def state(server) do
    GenServer.call(server, :state)
  end