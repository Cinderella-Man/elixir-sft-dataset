  defp merge_fields(id, key, b, o, t) do
    fields =
      (Map.keys(b) ++ Map.keys(o) ++ Map.keys(t))
      |> Enum.uniq()
      |> Enum.sort()

    {values, conflicts} =
      Enum.reduce(fields, {%{}, %{}}, fn field, {values, conflicts} ->
        bv = Map.get(b, field, :missing)
        ov = Map.get(o, field, :missing)
        tv = Map.get(t, field, :missing)

        cond do
          ov == tv -> {put_field(values, field, ov), conflicts}
          ov == bv -> {put_field(values, field, tv), conflicts}
          tv == bv -> {put_field(values, field, ov), conflicts}
          true -> {values, Map.put(conflicts, field, %{base: bv, ours: ov, theirs: tv})}
        end
      end)

    if map_size(conflicts) == 0 do
      {:merged, values}
    else
      {:conflict, %{key => id, type: :modify_modify, fields: conflicts}}
    end
  end