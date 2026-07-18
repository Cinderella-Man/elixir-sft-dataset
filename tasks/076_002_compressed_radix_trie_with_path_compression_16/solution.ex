  @doc "Returns the total number of nodes, including the root."
  @spec node_count(t) :: pos_integer
  def node_count(%__MODULE__{root: root}), do: count_nodes(root)