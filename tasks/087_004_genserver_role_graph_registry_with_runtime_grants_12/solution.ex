  # Can we reach `target` from `from` following inheritance edges?
  defp reachable?(inherits, from, target) do
    do_reach(inherits, [from], MapSet.new(), target)
  end