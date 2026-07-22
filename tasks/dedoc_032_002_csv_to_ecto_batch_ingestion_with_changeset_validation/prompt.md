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
defmodule CsvIngestion do
  require Logger

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Defaults
  # ---------------------------------------------------------------------------

  @default_batch_size 500
  @default_on_conflict :nothing
  @default_conflict_target []

  # ---------------------------------------------------------------------------
  # CSV parser definition
  # ---------------------------------------------------------------------------

  NimbleCSV.define(CsvIngestion.Parser, separator: ",", escape: "\"")

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def ingest(repo, schema, file_path, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    on_conflict = Keyword.get(opts, :on_conflict, @default_on_conflict)
    conflict_target = Keyword.get(opts, :conflict_target, @default_conflict_target)
    field_mapping = Keyword.get(opts, :field_mapping, nil)

    with :ok <- check_file(file_path),
         {:ok, rows} <- parse_csv(file_path) do
      cfg = %{
        batch_size: batch_size,
        on_conflict: on_conflict,
        conflict_target: conflict_target
      }

      {:ok, process_rows(repo, schema, rows, field_mapping, cfg)}
    end
  end

  # ---------------------------------------------------------------------------
  # File checks
  # ---------------------------------------------------------------------------

  defp check_file(path) do
    cond do
      not File.exists?(path) ->
        Logger.error("[CsvIngestion] File not found: #{inspect(path)}")
        {:error, :file_not_found}

      File.stat!(path).size == 0 ->
        Logger.error("[CsvIngestion] File is empty: #{inspect(path)}")
        {:error, :empty_file}

      true ->
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # CSV parsing
  # ---------------------------------------------------------------------------

  defp parse_csv(path) do
    raw = File.read!(path)

    # NimbleCSV.parse_string with skip_headers: false returns every row as a
    # list of fields; the first row is split off as the header list.
    parsed =
      raw
      |> CsvIngestion.Parser.parse_string(skip_headers: false)
      |> then(fn
        [] -> {[], []}
        [hdr | rows] -> {hdr, rows}
      end)

    case parsed do
      {_headers, _data} = pair -> {:ok, pair}
    end
  end

  # ---------------------------------------------------------------------------
  # Row processing
  # ---------------------------------------------------------------------------

  defp process_rows(repo, schema, {headers, data_rows}, field_mapping, cfg) do
    atom_headers = map_headers(headers, field_mapping)
    schema_keys = schema_field_set(schema)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    total = length(data_rows)

    # Validate each row via changeset; split into valid and invalid.
    {valid_rows, validation_errors} =
      data_rows
      # line 2 is the first data row
      |> Enum.with_index(2)
      |> Enum.reduce({[], []}, fn {cells, line_num}, {valid_acc, err_acc} ->
        attrs = build_attrs(cells, atom_headers, schema_keys)
        changeset = schema.changeset(struct(schema), attrs)

        if changeset.valid? do
          row =
            changeset.changes
            |> maybe_put_ts(:inserted_at, now, schema_keys)
            |> maybe_put_ts(:updated_at, now, schema_keys)

          {[row | valid_acc], err_acc}
        else
          {valid_acc, [{line_num, changeset.errors} | err_acc]}
        end
      end)

    valid_rows = Enum.reverse(valid_rows)
    validation_errors = Enum.reverse(validation_errors)
    invalid_count = length(validation_errors)

    # Batch-insert valid rows.
    initial_acc = %{
      total: total,
      inserted: 0,
      invalid: invalid_count,
      failed: 0,
      validation_errors: validation_errors
    }

    stats =
      valid_rows
      |> Enum.chunk_every(cfg.batch_size)
      |> Enum.reduce(initial_acc, fn batch, acc ->
        process_batch(repo, schema, batch, cfg, acc)
      end)

    Logger.info("[CsvIngestion] Finished. Final stats: #{format_stats(stats)}")
    stats
  end

  # ---------------------------------------------------------------------------
  # Header mapping
  # ---------------------------------------------------------------------------

  defp map_headers(headers, nil) do
    Enum.map(headers, fn h ->
      h
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/\s+/, "_")
      |> String.to_atom()
    end)
  end

  defp map_headers(headers, mapping) when is_map(mapping) do
    Enum.map(headers, fn h ->
      trimmed = String.trim(h)
      Map.get(mapping, trimmed, default_atom(trimmed))
    end)
  end

  defp default_atom(header) do
    header
    |> String.downcase()
    |> String.replace(~r/\s+/, "_")
    |> String.to_atom()
  end

  # ---------------------------------------------------------------------------
  # Attribute building
  # ---------------------------------------------------------------------------

  defp build_attrs(cells, atom_headers, schema_keys) do
    atom_headers
    |> Enum.zip(cells)
    |> Enum.filter(fn {k, _v} -> MapSet.member?(schema_keys, Atom.to_string(k)) end)
    |> Enum.map(fn {k, v} -> {k, normalize_value(v)} end)
    |> Map.new()
  end

  defp normalize_value(""), do: nil
  defp normalize_value(v), do: String.trim(v)

  # ---------------------------------------------------------------------------
  # Schema introspection
  # ---------------------------------------------------------------------------

  defp schema_field_set(schema) do
    schema.__schema__(:fields)
    |> Enum.map(&Atom.to_string/1)
    |> MapSet.new()
  end

  # ---------------------------------------------------------------------------
  # Timestamp injection
  # ---------------------------------------------------------------------------

  defp maybe_put_ts(row, field, value, schema_keys) do
    if MapSet.member?(schema_keys, Atom.to_string(field)) do
      Map.put_new(row, field, value)
    else
      row
    end
  end

  # ---------------------------------------------------------------------------
  # Batch processing
  # ---------------------------------------------------------------------------

  defp process_batch(repo, schema, batch, cfg, acc) do
    # Ecto forbids `:conflict_target` together with `on_conflict: :raise` (the
    # default), so only attach a conflict target for the conflict-handling modes.
    # With `:raise`, a duplicate key surfaces as a normal constraint error (caught
    # below and counted against this batch).
    insert_opts =
      case {cfg.on_conflict, cfg.conflict_target} do
        {:raise, _} ->
          [on_conflict: :raise]

        # An empty conflict target cannot be handed to Ecto (it rejects the
        # wrapped [:nothing]/[] as an unknown column) — omit the option, so
        # a default-opts ingest actually inserts instead of failing every
        # batch inside the rescue.
        {other, []} ->
          [on_conflict: other]

        {other, target} ->
          [on_conflict: other, conflict_target: target]
      end

    batch_size = length(batch)

    try do
      {count, _} = repo.insert_all(schema, batch, insert_opts)

      new_acc = %{acc | inserted: acc.inserted + count}

      Logger.info(
        "[CsvIngestion] Batch done — " <>
          "size: #{batch_size}, inserted: #{count}. " <>
          "Running totals — #{format_stats(new_acc)}"
      )

      new_acc
    rescue
      error ->
        Logger.error(
          "[CsvIngestion] Batch failed (#{batch_size} records skipped): " <>
            Exception.format(:error, error, __STACKTRACE__)
        )

        %{acc | failed: acc.failed + batch_size}
    catch
      kind, reason ->
        Logger.error(
          "[CsvIngestion] Batch failed with #{kind} " <>
            "(#{batch_size} records skipped): #{inspect(reason)}"
        )

        %{acc | failed: acc.failed + batch_size}
    end
  end

  # ---------------------------------------------------------------------------
  # Formatting
  # ---------------------------------------------------------------------------

  defp format_stats(%{total: t, inserted: i, invalid: inv, failed: f}) do
    "total=#{t} inserted=#{i} invalid=#{inv} failed=#{f}"
  end
end
```
