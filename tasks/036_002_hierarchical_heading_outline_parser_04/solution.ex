  # Finalise `node` and attach it as a child of the next open node, or as a root.
  defp attach(node, roots, [parent | rest]) do
    {roots, [%{parent | children: [finalize(node) | parent.children]} | rest]}
  end

  defp attach(node, roots, []) do
    {[finalize(node) | roots], []}
  end