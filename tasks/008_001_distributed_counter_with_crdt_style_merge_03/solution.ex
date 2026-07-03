  @spec compute_value(pn_state()) :: integer()
  defp compute_value(%{p: p, n: n}) do
    sum_map(p) - sum_map(n)
  end