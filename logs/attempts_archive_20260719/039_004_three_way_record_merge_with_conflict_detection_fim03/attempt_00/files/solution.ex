  def merge(base_list, ours_list, theirs_list, opts \\ []) do
    key = Keyword.get(opts, :key, :id)

    base = index_by(base_list, key)
    ours = index_by(ours_list, key)
    theirs = index_by(theirs_list, key)

    ids =
      (Map.keys(base) ++ Map.keys(ours) ++ Map.keys(theirs))
      |> Enum.uniq()
      |> Enum.sort()

    {merged, conflicts} =
      Enum.reduce(ids, {[], []}, fn id, {merged, conflicts} ->
        b = Map.get(base, id)
        o = Map.get(ours, id)
        t = Map.get(theirs, id)

        case resolve(id, key, b, o, t) do
          :drop -> {merged, conflicts}
          {:merged, record} -> {[record | merged], conflicts}
          {:conflict, entry} -> {merged, [entry | conflicts]}
        end
      end)

    %{merged: Enum.reverse(merged), conflicts: Enum.reverse(conflicts)}
  end