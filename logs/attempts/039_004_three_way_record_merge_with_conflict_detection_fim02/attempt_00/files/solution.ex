  defp resolve(id, key, b, o, t) do
    case {present?(b), present?(o), present?(t)} do
      {false, true, true} ->
        if o == t do
          {:merged, o}
        else
          {:conflict, %{key => id, type: :add_add, ours: o, theirs: t}}
        end

      {false, true, false} ->
        {:merged, o}

      {false, false, true} ->
        {:merged, t}

      {true, true, true} ->
        merge_fields(id, key, b, o, t)

      {true, true, false} ->
        if o == b do
          :drop
        else
          {:conflict, %{key => id, type: :delete_modify, deleted_by: :theirs, modified: o}}
        end

      {true, false, true} ->
        if t == b do
          :drop
        else
          {:conflict, %{key => id, type: :delete_modify, deleted_by: :ours, modified: t}}
        end

      {true, false, false} ->
        :drop
    end
  end