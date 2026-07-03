# Merges two G-Counters by taking the per-node maximum.
@spec merge_g_counters(g_counter(), g_counter()) :: g_counter()
defp merge_g_counters(local, remote) do
  Map.merge(local, remote, fn _node_id, l_val, r_val -> max(l_val, r_val) end)
end