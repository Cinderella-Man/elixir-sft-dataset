defmodule CsvIngestion do
  @moduledoc """
  Bulk ingestion of CSV files into an Ecto-backed database table.

  `CsvIngestion` reads a CSV file with `NimbleCSV`, validates every data row through the
  target schema's `changeset/2` function, and inserts the valid rows in batches using
  `Ecto.Repo.insert_all/3`.

  The ingestion pipeline is deliberately fault tolerant:

    * rows that fail changeset validation are skipped and reported (with their 1-based line
      number in the source file) instead of aborting the run;
    * a batch whose `insert_all/3` call raises is logged, counted as failed and the remaining
      batches still run;
    * missing or empty files return tagged error tuples rather than raising.

  ## Example

      iex> CsvIngestion.ingest(MyApp.Repo, MyApp.Product, "products.csv",
      ...>   batch_size: 1_000,
      ...>   on_conflict: :replace_all,
      ...>   conflict_target: :external_id,
      ...>   field_mapping: %{"Product ID" => :external_id, "Product Name" => :name}
      ...> )
      {:ok,
       %{
         total: 3,
         inserted: 2,
         invalid: 1,
         failed: 0,
         validation_errors: [{3, [name: {"can't be blank", [validation: :required]}]}]
       }}

  ## Options

    * `:batch_size` — number of valid records handed to each `insert_all/3` call (default `500`)
    * `:on_conflict` — passed straight through as `insert_all/3`'s `:on_conflict` (default
      `:nothing`)
    * `:conflict_target` — passed straight through as `insert_all/3`'s `:conflict_target`
      (default `:nothing`)
    * `:field_mapping` — optional map of CSV header string to schema field atom. When `nil`
      (the default) headers are snake_cased and converted to atoms directly.
  """

  require Logger

  NimbleCSV.define(CsvIngestion.Parser, separator: ",", escape: "\"")

  alias CsvIngestion.Parser

  @default_batch_size 500
  @timestamp_fields [:inserted_at, :updated_at]

  @typedoc "Aggregate statistics returned by a successful ingestion run."
  @type stats :: %{
          total: non_neg_integer(),
          inserted: non_neg_integer(),
          invalid: non_neg_integer(),
          failed: non_neg_integer(),
          validation_errors: [{pos_integer(), keyword()}]
        }

  @typedoc "Reasons an ingestion run can fail outright."
  @type reason :: :file_not_found | :empty_file | {:parse_error, String.t()}

  @doc """
  Ingests the CSV file at `file_path` into `schema` using `repo`.

  Every data row is validated with `schema.changeset(struct(schema), attrs)`. Valid rows are
  collected, chunked into batches of `:batch_size` and written with `repo.insert_all/3`.
  Invalid rows are skipped and reported through the `:validation_errors` key of the returned
  stats map.

  Returns `{:ok, stats}` when the file could be read and parsed — even when individual rows or
  whole batches failed — or `{:error, reason}` when the file is missing (`:file_not_found`) or
  zero bytes long (`:empty_file`).

  See the module documentation for the supported options.
  """
  @spec ingest(module(), module(), Path.t(), keyword()) :: {:ok, stats()} | {:error, reason()}
  def ingest(repo, schema, file_path, opts \\ []) do
    with :ok <- validate_file(file_path),
         {:ok, rows} <- parse_file(file_path, opts) do
      {records, invalid_count, validation_errors} = validate_rows(rows, schema)

      stats =
        insert_batches(repo, schema, records, opts, %{
          total: length(rows),
          inserted: 0,
          invalid: invalid_count,
          failed: 0,
          validation_errors: Enum.reverse(validation_errors)
        })

      {:ok, stats}
    end
  end

  # -- file handling ---------------------------------------------------------------------

  @spec validate_file(Path.t()) :: :ok | {:error, reason()}
  defp validate_file(file_path) do
    cond do
      not File.exists?(file_path) -> {:error, :file_not_found}
      file_size(file_path) == 0 -> {:error, :empty_file}
      true -> :ok
    end
  end

  @spec file_size(Path.t()) :: non_neg_integer()
  defp file_size(file_path) do
    case File.stat(file_path) do
      {:ok, %File.Stat{size: size}} -> size
      {:error, _posix} -> 0
    end
  end

  # Parses the whole file into a list of `{attrs, line_number}` tuples. The header occupies
  # line 1, so the first data row is line 2.
  @spec parse_file(Path.t(), keyword()) :: {:ok, [{map(), pos_integer()}]} | {:error, reason()}
  defp parse_file(file_path, opts) do
    mapping = Keyword.get(opts, :field_mapping)

    case File.read(file_path) do
      {:ok, contents} ->
        do_parse(contents, mapping)

      {:error, :enoent} ->
        {:error, :file_not_found}

      {:error, posix} ->
        Logger.error("CsvIngestion: unable to read #{file_path}: #{inspect(posix)}")
        {:error, posix}
    end
  end

  @spec do_parse(binary(), map() | nil) :: {:ok, [{map(), pos_integer()}]} | {:error, reason()}
  defp do_parse(contents, mapping) do
    case Parser.parse_string(contents, skip_headers: false) do
      [] ->
        {:ok, []}

      [header | data_rows] ->
        fields = header_fields(header, mapping)

        rows =
          data_rows
          |> Enum.with_index(2)
          |> Enum.map(fn {row, line} -> {build_attrs(fields, row), line} end)

        {:ok, rows}
    end
  rescue
    error -> {:error, {:parse_error, Exception.message(error)}}
  end

  @spec header_fields([String.t()], map() | nil) :: [atom()]
  defp header_fields(header, nil), do: Enum.map(header, &snake_case_atom/1)

  defp header_fields(header, mapping) when is_map(mapping) do
    Enum.map(header, fn column ->
      trimmed = String.trim(column)

      case Map.fetch(mapping, trimmed) do
        {:ok, field} -> field
        :error -> snake_case_atom(trimmed)
      end
    end)
  end

  @spec snake_case_atom(String.t()) :: atom()
  defp snake_case_atom(column) do
    column
    |> String.trim()
    |> String.replace(~r/[^\w]+/u, "_")
    |> Macro.underscore()
    |> String.replace(~r/_+/, "_")
    |> String.trim("_")
    |> String.to_atom()
  end

  # Zips the header fields with the row's cells. Missing trailing cells become `nil`; extra
  # cells beyond the header width are ignored.
  @spec build_attrs([atom()], [String.t()]) :: map()
  defp build_attrs(fields, row) do
    fields
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {field, index}, acc ->
      Map.put(acc, field, Enum.at(row, index))
    end)
  end

  # -- validation ------------------------------------------------------------------------

  @spec validate_rows([{map(), pos_integer()}], module()) ::
          {[map()], non_neg_integer(), [{pos_integer(), keyword()}]}
  defp validate_rows(rows, schema) do
    Enum.reduce(rows, {[], 0, []}, fn {attrs, line}, {records, invalid, errors} ->
      changeset = schema.changeset(struct(schema), attrs)

      if changeset.valid? do
        {[changeset.changes | records], invalid, errors}
      else
        {records, invalid + 1, [{line, changeset.errors} | errors]}
      end
    end)
    |> then(fn {records, invalid, errors} -> {Enum.reverse(records), invalid, errors} end)
  end

  # -- insertion -------------------------------------------------------------------------

  @spec insert_batches(module(), module(), [map()], keyword(), stats()) :: stats()
  defp insert_batches(_repo, _schema, [], _opts, stats) do
    Logger.info(
      "CsvIngestion: nothing to insert — total=#{stats.total} inserted=#{stats.inserted} " <>
        "invalid=#{stats.invalid} failed=#{stats.failed}"
    )

    stats
  end

  defp insert_batches(repo, schema, records, opts, stats) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    insert_opts = insert_opts(opts)
    timestamp_fields = timestamp_fields(schema)

    records
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce(stats, fn batch, acc ->
      acc
      |> insert_batch(repo, schema, stamp(batch, timestamp_fields), insert_opts)
      |> tap(&log_progress/1)
    end)
  end

  @spec insert_batch(stats(), module(), module(), [map()], keyword()) :: stats()
  defp insert_batch(stats, repo, schema, batch, insert_opts) do
    {count, _returning} = repo.insert_all(schema, batch, insert_opts)
    %{stats | inserted: stats.inserted + normalize_count(count, length(batch))}
  rescue
    error ->
      Logger.error(
        "CsvIngestion: batch of #{length(batch)} row(s) failed to insert: " <>
          Exception.message(error)
      )

      %{stats | failed: stats.failed + length(batch)}
  end

  @spec normalize_count(term(), non_neg_integer()) :: non_neg_integer()
  defp normalize_count(count, _batch_length) when is_integer(count) and count >= 0, do: count
  defp normalize_count(_count, batch_length), do: batch_length

  @spec insert_opts(keyword()) :: keyword()
  defp insert_opts(opts) do
    [
      on_conflict: Keyword.get(opts, :on_conflict, :nothing),
      conflict_target: Keyword.get(opts, :conflict_target, :nothing)
    ]
  end

  @spec log_progress(stats()) :: :ok
  defp log_progress(stats) do
    Logger.info(
      "CsvIngestion: batch complete — total=#{stats.total} inserted=#{stats.inserted} " <>
        "invalid=#{stats.invalid} failed=#{stats.failed}"
    )
  end

  # -- timestamps ------------------------------------------------------------------------

  @spec timestamp_fields(module()) :: [atom()]
  defp timestamp_fields(schema) do
    schema_fields =
      if function_exported?(schema, :__schema__, 1) do
        schema.__schema__(:fields)
      else
        []
      end

    Enum.filter(@timestamp_fields, &(&1 in schema_fields))
  end

  @spec stamp([map()], [atom()]) :: [map()]
  defp stamp(batch, []), do: batch

  defp stamp(batch, fields) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    defaults = Map.new(fields, &{&1, now})

    Enum.map(batch, fn record -> Map.merge(defaults, record) end)
  end
end