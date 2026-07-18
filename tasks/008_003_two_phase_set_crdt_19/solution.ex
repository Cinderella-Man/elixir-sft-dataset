  @doc """
  Returns the raw internal state of the set.

  The returned map has the form:

      %{
        added:   MapSet of all elements ever added,
        removed: MapSet of all elements ever removed (tombstones)
      }

  This value can be sent to a remote node and passed to `TwoPhaseSet.merge/2`.
  """
  @spec state(server()) :: tp_state()
  def state(server) do
    GenServer.call(server, :state)
  end