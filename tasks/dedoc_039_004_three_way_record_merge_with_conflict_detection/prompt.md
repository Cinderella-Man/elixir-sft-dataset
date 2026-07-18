# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule RecordMerge do
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

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp index_by(records, key) do
    Map.new(records, fn record -> {Map.fetch!(record, key), record} end)
  end

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

  defp put_field(values, _field, :missing), do: values
  defp put_field(values, field, value), do: Map.put(values, field, value)

  defp present?(nil), do: false
  defp present?(_), do: true
end
```
