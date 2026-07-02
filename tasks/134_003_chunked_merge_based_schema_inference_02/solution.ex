  def merge(a, b) do
    %{
      names: a.names || b.names,
      ncols: max(a.ncols, b.ncols),
      categories:
        Map.merge(a.categories, b.categories, fn _index, s1, s2 -> MapSet.union(s1, s2) end)
    }
  end