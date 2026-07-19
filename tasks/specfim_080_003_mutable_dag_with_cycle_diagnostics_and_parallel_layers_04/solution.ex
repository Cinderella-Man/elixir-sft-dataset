  @spec add_edge(t(), vertex(), vertex()) ::
          {:ok, t()} | {:error, {:cycle, [vertex()]}} | {:error, :vertex_not_found}