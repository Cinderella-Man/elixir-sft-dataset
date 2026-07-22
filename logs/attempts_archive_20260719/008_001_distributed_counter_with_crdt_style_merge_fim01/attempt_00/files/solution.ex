  @spec merge_states(pn_state(), pn_state()) :: pn_state()
  defp merge_states(%{p: lp, n: ln}, %{p: rp, n: rn}) do
    %{
      p: merge_g_counters(lp, rp),
      n: merge_g_counters(ln, rn)
    }
  end