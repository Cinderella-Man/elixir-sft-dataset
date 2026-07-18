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
defmodule MultiSeriesResampler do
  @valid_agg [:last, :first, :mean, :sum, :count, :max, :min]
  @valid_fill [nil, :forward]

  def resample(series, interval_ms, opts \\ [])

  def resample(series, interval_ms, opts)
      when is_map(series) and is_integer(interval_ms) and interval_ms > 0 do
    agg = fetch_opt!(opts, :agg, :last, @valid_agg)
    fill = fetch_opt!(opts, :fill, nil, @valid_fill)

    sorted =
      Map.new(series, fn {name, points} ->
        {name, Enum.sort_by(points, &elem(&1, 0))}
      end)

    all_ts = for {_name, pts} <- sorted, {ts, _v} <- pts, do: ts

    case all_ts do
      [] ->
        []

      _ ->
        first_bucket = floor_bucket(Enum.min(all_ts), interval_ms)
        last_bucket = floor_bucket(Enum.max(all_ts), interval_ms)
        names = Map.keys(sorted)

        grouped =
          Map.new(sorted, fn {name, pts} ->
            {name, Enum.group_by(pts, fn {ts, _v} -> floor_bucket(ts, interval_ms) end)}
          end)

        buckets =
          first_bucket
          |> Stream.iterate(&(&1 + interval_ms))
          |> Stream.take_while(&(&1 <= last_bucket))
          |> Enum.to_list()

        {rows, _last} =
          Enum.map_reduce(buckets, empty_last(names), fn bucket_start, last_values ->
            build_row(names, grouped, bucket_start, agg, fill, last_values)
          end)

        rows
    end
  end

  def resample(series, interval_ms, _opts)
      when is_map(series) and not is_integer(interval_ms) do
    raise ArgumentError, "interval_ms must be a positive integer, got: #{inspect(interval_ms)}"
  end

  def resample(series, interval_ms, _opts)
      when is_map(series) and interval_ms <= 0 do
    raise ArgumentError, "interval_ms must be positive, got: #{interval_ms}"
  end

  # --------------------------------------------------------------------------
  # Private helpers
  # --------------------------------------------------------------------------

  defp build_row(names, grouped, bucket_start, agg, fill, last_values) do
    {row, next_last} =
      Enum.reduce(names, {%{}, last_values}, fn name, {acc_row, acc_last} ->
        agg_value =
          case Map.fetch(grouped[name], bucket_start) do
            {:ok, pts} -> aggregate(pts, agg)
            :error -> nil
          end

        filled =
          case {agg_value, fill} do
            {nil, :forward} -> Map.get(acc_last, name)
            {nil, nil} -> nil
            {v, _} -> v
          end

        new_last =
          if agg_value != nil,
            do: Map.put(acc_last, name, agg_value),
            else: acc_last

        {Map.put(acc_row, name, filled), new_last}
      end)

    {{bucket_start, row}, next_last}
  end

  defp empty_last(names), do: Map.new(names, &{&1, nil})

  # Floored division, not truncation: a negative timestamp must land in the
  # bucket at or below it (floor(t / interval) * interval), matching the grid
  # rule for the earliest timestamp.
  defp floor_bucket(ts, interval_ms), do: Integer.floor_div(ts, interval_ms) * interval_ms

  defp aggregate(points, :last), do: points |> List.last() |> elem(1)
  defp aggregate(points, :first), do: points |> hd() |> elem(1)
  defp aggregate(points, :count), do: length(points)
  defp aggregate(points, :sum), do: Enum.reduce(points, 0, fn {_t, v}, acc -> acc + v end)
  defp aggregate(points, :max), do: points |> Enum.map(&elem(&1, 1)) |> Enum.max()
  defp aggregate(points, :min), do: points |> Enum.map(&elem(&1, 1)) |> Enum.min()

  defp aggregate(points, :mean) do
    {sum, count} =
      Enum.reduce(points, {0, 0}, fn {_t, v}, {s, c} -> {s + v, c + 1} end)

    sum / count
  end

  defp fetch_opt!(opts, key, default, valid) do
    value = Keyword.get(opts, key, default)

    unless value in valid do
      raise ArgumentError,
            "invalid value #{inspect(value)} for option :#{key}; " <>
              "expected one of #{inspect(valid)}"
    end

    value
  end
end
```
