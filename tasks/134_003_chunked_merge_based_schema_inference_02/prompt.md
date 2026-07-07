Implement the public `merge/2` function. It takes two partials `a` and `b` (each a
map with `:names`, `:ncols`, and `:categories` keys) and combines them into a single
partial. The operation must be associative, commutative, and idempotent: `:names` is
the first non-`nil` header list of the two (`a.names || b.names`), `:ncols` is the
maximum of the two column counts, and `:categories` is the per-index union of the two
category maps (for any index present in both, union the two `MapSet`s; indices present
in only one are carried over unchanged). Return the resulting partial map.

```elixir
defmodule MergeSchema do
  @moduledoc """
  Chunk-and-merge CSV schema inference using only the OTP standard library.

  A CSV fragment is reduced by `partial/2` to a compact state — header names,
  a column count, and per-column `MapSet`s of observed non-null categories.
  Partials combine with an associative, commutative, idempotent `merge/2`
  (per-index set union, max column count, first non-nil header list), and
  `finalize/1` resolves the accumulated categories into a schema map. This lets
  a large file be inferred in independent slices and folded together.
  """

  @type category :: atom()
  @type partial :: %{
          names: [String.t()] | nil,
          ncols: non_neg_integer(),
          categories: %{optional(non_neg_integer()) => MapSet.t(category())}
        }
  @type schema :: %{optional(String.t()) => atom()}
  @type cell :: {String.t(), boolean()}
  @type row :: [cell()]

  @doc """
  Parse a CSV fragment into an opaque partial inference state (a plain map).

  With `headers: true` (the default) the first record supplies column names;
  with `headers: false` every record is data and columns are positional. The
  returned map has `:names`, `:ncols`, and `:categories` keys.
  """
  @spec partial(String.t(), keyword()) :: partial()
  def partial(csv, opts \\ []) when is_binary(csv) do
    headers? = Keyword.get(opts, :headers, true)

    records = parse_csv(csv)
    {names, data_rows} = split_records(records, headers?)

    ncols =
      [length(names || [])]
      |> Kernel.++(Enum.map(data_rows, &length/1))
      |> Enum.max()

    %{names: names, ncols: ncols, categories: build_categories(data_rows)}
  end

  @doc """
  Combine two partials into one.

  The operation is associative, commutative, and idempotent: `:categories` are
  unioned per index, `:ncols` is the maximum, and `:names` is the first
  non-`nil` header list.
  """
  @spec merge(partial(), partial()) :: partial()
  def merge(a, b) do
    # TODO
  end

  @doc """
  Resolve a partial into a schema map `%{"column_name" => :inferred_type}`.

  Column names come from `:names` when present, otherwise positional names
  `"column_1"`..`"column_ncols"` are generated from `:ncols`.
  """
  @spec finalize(partial()) :: schema()
  def finalize(%{names: names, ncols: ncols, categories: categories}) do
    resolved_names = names || Enum.map(1..ncols//1, fn i -> "column_#{i}" end)

    resolved_names
    |> Enum.with_index()
    |> Map.new(fn {name, index} ->
      {name, resolve(Map.get(categories, index, MapSet.new()))}
    end)
  end

  @doc """
  Convenience wrapper equivalent to `finalize(partial(csv, opts))`.
  """
  @spec infer_string(String.t(), keyword()) :: schema()
  def infer_string(csv, opts \\ []) do
    csv
    |> partial(opts)
    |> finalize()
  end

  # --- Category accumulation ------------------------------------------------

  @spec build_categories([row()]) :: %{optional(non_neg_integer()) => MapSet.t(category())}
  defp build_categories(rows) do
    Enum.reduce(rows, %{}, fn row, acc ->
      row
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {cell, index}, inner ->
        case categorize(cell) do
          :null -> inner
          category -> Map.update(inner, index, MapSet.new([category]), &MapSet.put(&1, category))
        end
      end)
    end)
  end

  @spec resolve(MapSet.t(category())) :: atom()
  defp resolve(set) do
    case MapSet.to_list(set) do
      [] -> :string
      [category] -> category
      many -> if Enum.all?(many, &(&1 in [:integer, :float])), do: :float, else: :string
    end
  end

  # --- Schema helpers -------------------------------------------------------

  @spec split_records([row()], boolean()) :: {[String.t()] | nil, [row()]}
  defp split_records([], true), do: {[], []}

  defp split_records([header | rest], true) do
    {Enum.map(header, fn {value, _quoted?} -> value end), rest}
  end

  defp split_records(records, false), do: {nil, records}

  # --- Per-cell classification ---------------------------------------------

  @spec categorize(cell()) :: atom()
  defp categorize({"", false}), do: :null
  defp categorize({_value, true}), do: :string
  defp categorize({value, false}), do: classify(value)

  @spec classify(String.t()) :: atom()
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

  defp boolean?(value), do: String.downcase(value) in ["true", "false"]

  defp integer?(value), do: Regex.match?(~r/^[+-]?\d+$/, value)

  defp float?(value), do: Regex.match?(~r/^[+-]?\d+\.\d+$/, value)

  defp date?(value) do
    cond do
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, value) ->
        [y, m, d] = String.split(value, "-")
        valid_date?(to_int(y), to_int(m), to_int(d))

      Regex.match?(~r/^\d{2}\/\d{2}\/\d{4}$/, value) ->
        [m, d, y] = String.split(value, "/")
        valid_date?(to_int(y), to_int(m), to_int(d))

      true ->
        false
    end
  end

  defp datetime?(value) do
    cond do
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/, value) ->
        valid_datetime?(value, "T")

      Regex.match?(~r/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/, value) ->
        valid_datetime?(value, " ")

      true ->
        false
    end
  end

  defp valid_date?(year, month, day) do
    match?({:ok, _}, Date.new(year, month, day))
  end

  defp valid_datetime?(value, sep) do
    [date_part, time_part] = String.split(value, sep, parts: 2)
    [y, m, d] = String.split(date_part, "-")
    [h, mi, s] = String.split(time_part, ":")

    result =
      NaiveDateTime.new(
        to_int(y),
        to_int(m),
        to_int(d),
        to_int(h),
        to_int(mi),
        to_int(s)
      )

    match?({:ok, _}, result)
  end

  defp to_int(value), do: String.to_integer(value)

  # --- CSV parsing ---------------------------------------------------------

  @spec parse_csv(String.t()) :: [row()]
  defp parse_csv(content) do
    case strip_one_newline(content) do
      "" -> []
      stripped -> parse_chars(stripped, "", false, false, [], [])
    end
  end

  defp strip_one_newline(content) do
    size = byte_size(content)

    case content do
      <<prefix::binary-size(^size - 1), "\n">> when size > 0 -> prefix
      _ -> content
    end
  end

  defp parse_chars(<<>>, acc, quoted?, _in_q?, fields, records) do
    record = Enum.reverse([{acc, quoted?} | fields])
    Enum.reverse([record | records])
  end

  defp parse_chars(<<"\"\"", rest::binary>>, acc, quoted?, true, fields, records) do
    parse_chars(rest, acc <> "\"", quoted?, true, fields, records)
  end

  defp parse_chars(<<"\"", rest::binary>>, acc, quoted?, true, fields, records) do
    parse_chars(rest, acc, quoted?, false, fields, records)
  end

  defp parse_chars(<<c::utf8, rest::binary>>, acc, quoted?, true, fields, records) do
    parse_chars(rest, acc <> <<c::utf8>>, quoted?, true, fields, records)
  end

  defp parse_chars(<<"\"", rest::binary>>, acc, _quoted?, false, fields, records) do
    parse_chars(rest, acc, true, true, fields, records)
  end

  defp parse_chars(<<",", rest::binary>>, acc, quoted?, false, fields, records) do
    parse_chars(rest, "", false, false, [{acc, quoted?} | fields], records)
  end

  defp parse_chars(<<"\n", rest::binary>>, acc, quoted?, false, fields, records) do
    record = Enum.reverse([{acc, quoted?} | fields])
    parse_chars(rest, "", false, false, [], [record | records])
  end

  defp parse_chars(<<c::utf8, rest::binary>>, acc, quoted?, false, fields, records) do
    parse_chars(rest, acc <> <<c::utf8>>, quoted?, false, fields, records)
  end
end
```