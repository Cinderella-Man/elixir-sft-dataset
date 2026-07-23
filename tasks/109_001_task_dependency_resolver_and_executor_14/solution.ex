  # A stuck node that nothing in the stuck set depends on cannot be part of
  # any cycle (every cycle member has a dependent inside the cycle) — it only
  # feeds on one. Trimming such nodes to a fixed point leaves exactly the
  # cycle participants.
  defp cycle_members(in_degree, dependents) do
    trim_feeders(MapSet.new(Map.keys(in_degree)), dependents)
  end