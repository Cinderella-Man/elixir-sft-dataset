  @doc """
  Sets the flag's own state to percentage rollout mode with `pct` (0–100),
  preserving its prerequisites.
  """
  @spec enable_for_percentage(atom(), 0..100) :: :ok
  def enable_for_percentage(flag, pct)
      when is_integer(pct) and pct >= 0 and pct <= 100 do
    GenServer.call(server(), {:set_state, flag, {:percentage, pct}})
  end