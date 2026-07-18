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
defmodule CounterResampler do
  @valid_mode [:delta, :rate]
  @valid_reset [:detect, :raw]
  @valid_fill [:zero, nil]

  def resample(data, interval_ms, opts \\ [])

  def resample(data, interval_ms, opts)
      when is_list(data) and is_integer(interval_ms) and interval_ms > 0 do
    mode = fetch_opt!(opts, :mode, :delta, @valid_mode)
    reset = fetch_opt!(opts, :reset, :detect, @valid_reset)
    fill = fetch_opt!(opts, :fill, :zero, @valid_fill)

    do_resample(data, interval_ms, mode, reset, fill)
  end

  def resample(_data, interval_ms, _opts) do
    raise ArgumentError,
          "interval_ms must be a positive integer, got: #{inspect(interval_ms)}"
  end

  # --------------------------------------------------------------------------
  # Private helpers
  # --------------------------------------------------------------------------

  defp do_resample([], _interval_ms, _mode, _reset, _fill), do: []

  defp do_resample(data, interval_ms, mode, reset, fill) do
    sorted = Enum.sort_by(data, &elem(&1, 0))

    {min_ts, _} = hd(sorted)
    {max_ts, _} = List.last(sorted)

    first_bucket = floor_bucket(min_ts, interval_ms)
    last_bucket = floor_bucket(max_ts, interval_ms)

    increments =
      sorted
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce(%{}, fn [{_t0, v0}, {t1, v1}], acc ->
        inc = increment(v0, v1, reset)
        bucket = floor_bucket(t1, interval_ms)
        Map.update(acc, bucket, inc, &(&1 + inc))
      end)

    first_bucket
    |> Stream.iterate(&(&1 + interval_ms))
    |> Stream.take_while(&(&1 <= last_bucket))
    |> Enum.map(fn bucket_start ->
      value =
        case Map.fetch(increments, bucket_start) do
          {:ok, inc} -> project(inc, mode, interval_ms)
          :error -> empty_value(mode, interval_ms, fill)
        end

      {bucket_start, value}
    end)
  end

  defp increment(v0, v1, :raw), do: v1 - v0

  defp increment(v0, v1, :detect) do
    if v1 < v0, do: v1, else: v1 - v0
  end

  defp project(inc, :delta, _interval_ms), do: inc
  defp project(inc, :rate, interval_ms), do: inc / (interval_ms / 1000)

  defp empty_value(_mode, _interval_ms, nil), do: nil
  defp empty_value(mode, interval_ms, :zero), do: project(0, mode, interval_ms)

  defp floor_bucket(ts, interval_ms), do: Integer.floor_div(ts, interval_ms) * interval_ms

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
