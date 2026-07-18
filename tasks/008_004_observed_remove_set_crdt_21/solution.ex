  @doc """
  Returns the raw internal state of the set.

  The returned map has the form:

      %{
        entries:    %{element => MapSet.t({node_id, counter})},
        tombstones: MapSet.t({node_id, counter}),
        clock:      %{node_id => counter}
      }
  """
  @spec state(server()) :: or_state()
  def state(server) do
    GenServer.call(server, :state)
  end