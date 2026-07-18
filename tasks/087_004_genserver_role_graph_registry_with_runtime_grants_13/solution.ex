  # The set containing `role` and every role reachable via inheritance edges.
  defp closure(inherits, role) do
    build_closure(inherits, [role], MapSet.new())
  end