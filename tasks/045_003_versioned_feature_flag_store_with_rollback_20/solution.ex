  @doc """
  Puts `flag` into `:percentage` mode with `pct` (an integer 0–100),
  recording a new version. Returns `:ok`.
  """
  @spec enable_for_percentage(atom(), 0..100) :: :ok
  def enable_for_percentage(flag, pct)
      when is_integer(pct) and pct >= 0 and pct <= 100 do
    GenServer.call(server(), {:write, flag, {:percentage, pct}})
  end