  # Converts a list of string-keyed JSON maps into the atom-keyed maps that
  # `insert_all` expects, filtering to only the columns the schema knows about
  # and injecting `inserted_at` / `updated_at` when the schema declares them.
  @spec prepare_rows(list(map()), MapSet.t(String.t())) :: list(map())
  defp prepare_rows(raw_rows, schema_keys) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Enum.map(raw_rows, fn row ->
      base =
        row
        |> Enum.filter(fn {k, _v} -> MapSet.member?(schema_keys, k) end)
        |> Enum.map(fn {k, v} ->
          # Safe: the atom already exists because it was interned when the
          # schema module was compiled.
          {String.to_existing_atom(k), v}
        end)
        |> Map.new()

      # Only inject timestamps if the schema actually has them; avoids errors
      # on schemas that do not call `timestamps()`.
      base
      |> maybe_put_new(:inserted_at, now, schema_keys)
      |> maybe_put_new(:updated_at, now, schema_keys)
    end)
  end