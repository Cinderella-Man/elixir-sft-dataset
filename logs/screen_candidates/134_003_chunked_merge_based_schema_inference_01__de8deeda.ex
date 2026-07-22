defmodule MergeSchema do
  @moduledoc """
  Chunked, merge-based CSV schema inference.

  A large CSV file can be split into independent fragments. Each fragment is reduced to a
  compact *partial* inference state via `partial/2`. Partials combine with `merge/2`, which is
  associative, commutative and idempotent, so fragments may be processed in any order (or
  concurrently) and folded together. `finalize/1` resolves a partial into a schema map of
  `%{"column_name" => :inferred_type}`.

  The inferred type of a column is one of `:string`, `:integer`, `:float`, `:boolean`, `:date`
  or `:datetime`.

  ## Partial representation

  A partial is a plain map with exactly these keys:

    * `:names` — the header column-name strings for the fragment, or `nil` when parsed with
      `headers: false`.
    * `:ncols` — the number of columns observed (max of the header length and every data row's
      field count).
    * `:categories` — a map from 0-based column index to a `MapSet` of the non-null cell
      categories seen in that column. Nulls are never recorded.

  ## Example

      iex> a = MergeSchema.partial("id,score\\n1,1.5\\n")
      iex> b = MergeSchema.partial("2,3\\n", headers: false)
      iex> MergeSchema.finalize(MergeSchema.merge(a, b))
      %{"id" => :integer, "score" => :float}
  """

  @type category :: :string | :integer | :float | :boolean | :date | :datetime
  @type partial :: %{
          names: [String.t()] | nil,
          ncols: non_neg_integer(),
          categories: %{non_neg_integer() => MapSet.t(category())}
        }
  @type schema :: %{String.t() => category()}

  @numeric MapSet.new([:integer, :float])

  @doc """
  Parses a CSV fragment and returns an opaque partial inference state.

  ## Options

    * `:headers` — when `true` (the default), the first record of the fragment is a header row
      supplying column names. When `false`, all records are data and columns are positional.

  ## Examples

      iex> MergeSchema.partial("a\\n1\\n").ncols
      1
  """
  @spec partial(String.t(), keyword()) :: partial()
  def partial(csv, opts \\ []) when is_binary(csv) and is_list(opts) do
    headers? = Keyword.get(opts, :headers, true)
    records = parse_csv(csv)

    {names, rows} =
      case {headers?, records} do
        {true, [header | rest]} -> {Enum.map(header, &elem(&1, 0)), rest}
        {true, []} -> {[], []}
        {false, all} -> {nil, all}
      end

    ncols = Enum.reduce(rows, length(names || []), &max(length(&1), &2))
    %{names: names, ncols: ncols, categories: collect_categories(rows)}
  end

  @doc """
  Combines two partials into one.

  The operation is associative, commutative and idempotent: category sets are unioned per
  column index, `:ncols` takes the maximum, and `:names` takes the first non-`nil` of the two.

  ## Examples

      iex> MergeSchema.merge(MergeSchema.partial("a\\n1\\n"), MergeSchema.partial("a\\n1\\n")).ncols
      1
  """
  @spec merge(partial(), partial()) :: partial()
  def merge(a, b) when is_map(a) and is_map(b) do
    categories =
      Map.merge(a.categories, b.categories, fn _idx, sa, sb -> MapSet.union(sa, sb) end)

    %{names: a.names || b.names, ncols: max(a.ncols, b.ncols), categories: categories}
  end

  @doc """
  Resolves a partial into a schema map of `%{"column_name" => :inferred_type}`.

  Column names come from `:names` when present, otherwise positional names `"column_1"` through
  `"column_<ncols>"` are generated.

  ## Examples

      iex> MergeSchema.finalize(MergeSchema.partial("flag\\ntrue\\n"))
      %{"flag" => :boolean}
  """
  @spec finalize(partial()) :: schema()
  def finalize(%{names: names, ncols: ncols, categories: categories}) do
    names
    |> column_names(ncols)
    |> Enum.with_index()
    |> Map.new(fn {name, idx} ->
      {name, resolve(Map.get(categories, idx, MapSet.new()))}
    end)
  end

  @doc """
  Infers a schema directly from a CSV string.

  Equivalent to `finalize(partial(csv, opts))`; accepts the same options as `partial/2`.

  ## Examples

      iex> MergeSchema.infer_string("n\\n1\\n2\\n")
      %{"n" => :integer}
  """
  @spec infer_string(String.t(), keyword()) :: schema()
  def infer_string(csv, opts \\ []) when is_binary(csv) and is_list(opts) do
    csv |> partial(opts) |> finalize()
  end

  # ── Column names ──────────────────────────────────────────────────────────────────────────

  @spec column_names([String.t()] | nil, non_neg_integer()) :: [String.t()]
  defp column_names(nil, ncols), do: Enum.map(1..ncols//1, &"column_#{&1}")
  defp column_names(names, _ncols), do: names

  # ── Category collection ───────────────────────────────────────────────────────────────────

  @spec collect_categories([[{String.t(), boolean()}]]) ::
          %{non_neg_integer() => MapSet.t(category())}
  defp collect_categories(rows) do
    Enum.reduce(rows, %{}, fn row, acc ->
      row
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {field, idx}, inner ->
        case categorize(field) do
          nil ->
            inner

          cat ->
            Map.update(inner, idx, MapSet.new([cat]), &MapSet.put(&1, cat))
        end
      end)
    end)
  end

  # Returns nil for a null cell (an unquoted empty field), otherwise the cell's category.
  @spec categorize({String.t(), boolean()}) :: category() | nil
  defp categorize({"", false}), do: nil
  defp categorize({_value, true}), do: :string
  defp categorize({value, false}), do: classify(value)

  @spec classify(String.t()) :: category()
  defp classify(value) do
    cond do
      boolean?(value) -> :boolean
      integer?(value) -> :integer
      float?(value) -> :float
      date?(value) -> :date
      datetime?(value) -> :datetime
      true -> :string
    end
  end

  @spec boolean?(String.t()) :: boolean()
  defp boolean?(value), do: String.downcase(value) in ["true", "false"]

  @spec integer?(String.t()) :: boolean()
  defp integer?(value), do: Regex.match?(~r/^[+-]?\d+$/, value)

  @spec float?(String.t()) :: boolean()
  defp float?(value), do: Regex.match?(~r/^[+-]?\d+\.\d+$/, value)

  @spec date?(String.t()) :: boolean()
  defp date?(value) do
    iso_date?(value) or us_date?(value)
  end

  @spec iso_date?(String.t()) :: boolean()
  defp iso_date?(value) do
    with true <- Regex.match?(~r{^\d{4}-\d{2}-\d{2}$}, value),
         {:ok, _date} <- Date.from_iso8601(value) do
      true
    else
      _other -> false
    end
  end

  @spec us_date?(String.t()) :: boolean()
  defp us_date?(value) do
    case Regex.run(~r{^(\d{2})/(\d{2})/(\d{4})$}, value) do
      [_all, mm, dd, yyyy] -> valid_date?(yyyy, mm, dd)
      _other -> false
    end
  end

  @spec datetime?(String.t()) :: boolean()
  defp datetime?(value) do
    case Regex.run(~r/^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})$/, value) do
      [_all, date, time] -> iso_date?(date) and valid_time?(time)
      _other -> false
    end
  end

  @spec valid_date?(String.t(), String.t(), String.t()) :: boolean()
  defp valid_date?(yyyy, mm, dd) do
    match?({:ok, _date}, Date.from_iso8601("#{yyyy}-#{mm}-#{dd}"))
  end

  @spec valid_time?(String.t()) :: boolean()
  defp valid_time?(time), do: match?({:ok, _time}, Time.from_iso8601(time))

  # ── CSV parsing ───────────────────────────────────────────────────────────────────────────

  # Returns a list of records; each record is a list of `{value, quoted?}` field tuples.
  @spec parse_csv(String.t()) :: [[{String.t(), boolean()}]]
  defp parse_csv(""), do: []

  defp parse_csv(csv) do
    csv
    |> drop_trailing_newline()
    |> case do
      "" -> []
      body -> parse_records(body, [], [], "", false, false)
    end
  end

  @spec drop_trailing_newline(String.t()) :: String.t()
  defp drop_trailing_newline(csv) do
    if String.ends_with?(csv, "\n"), do: binary_part(csv, 0, byte_size(csv) - 1), else: csv
  end

  # State machine over the fragment body.
  #
  #   records — completed records, reversed
  #   fields  — completed fields of the current record, reversed
  #   buf     — the current field's accumulated characters
  #   quoted? — whether the current field was (at any point) quoted
  #   inq?    — whether the cursor is inside a quoted section
  @spec parse_records(
          String.t(),
          [[{String.t(), boolean()}]],
          [{String.t(), boolean()}],
          String.t(),
          boolean(),
          boolean()
        ) :: [[{String.t(), boolean()}]]
  defp parse_records(<<>>, records, fields, buf, quoted?, _inq?) do
    Enum.reverse([Enum.reverse([{buf, quoted?} | fields]) | records])
  end

  defp parse_records(<<?", ?", rest::binary>>, records, fields, buf, quoted?, true) do
    parse_records(rest, records, fields, buf <> "\"", quoted?, true)
  end

  defp parse_records(<<?", rest::binary>>, records, fields, buf, _quoted?, true) do
    parse_records(rest, records, fields, buf, true, false)
  end

  defp parse_records(<<?", rest::binary>>, records, fields, buf, _quoted?, false) do
    parse_records(rest, records, fields, buf, true, true)
  end

  defp parse_records(<<?,, rest::binary>>, records, fields, buf, quoted?, false) do
    parse_records(rest, records, [{buf, quoted?} | fields], "", false, false)
  end

  defp parse_records(<<?\n, rest::binary>>, records, fields, buf, quoted?, false) do
    record = Enum.reverse([{buf, quoted?} | fields])
    parse_records(rest, [record | records], [], "", false, false)
  end

  defp parse_records(<<char::utf8, rest::binary>>, records, fields, buf, quoted?, inq?) do
    parse_records(rest, records, fields, <<buf::binary, char::utf8>>, quoted?, inq?)
  end

  # ── Resolution ────────────────────────────────────────────────────────────────────────────

  @spec resolve(MapSet.t(category())) :: category()
  defp resolve(set) do
    case MapSet.size(set) do
      0 ->
        :string

      1 ->
        set |> MapSet.to_list() |> hd()

      _many ->
        if MapSet.subset?(set, @numeric), do: :float, else: :string
    end
  end
end