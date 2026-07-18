  @doc """
  Returns the raw internal state of the counter.

  The returned map has the form:

      %{
        p: %{node_id => total_increments, ...},
        n: %{node_id => total_decrements, ...}
      }

  This value can be sent to a remote node and passed to `Counter.merge/2`
  to synchronise state.
  """
  @spec state(server()) :: pn_state()
  def state(server) do
    GenServer.call(server, :state)
  end