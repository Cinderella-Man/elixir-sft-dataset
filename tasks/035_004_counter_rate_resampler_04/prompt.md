Implement the private `project/3` function. It converts a raw per-bucket
increment into the value that should be emitted for that bucket, according to the
requested `mode`.

`project/3` receives three arguments: `inc` (the summed increment attributed to a
bucket), `mode` (`:delta` or `:rate`), and `interval_ms` (the bucket width in
milliseconds).

- In `:delta` mode it emits the increment unchanged (`interval_ms` is irrelevant).
- In `:rate` mode it emits the increment divided by the interval length in
  seconds — that is, `inc / (interval_ms / 1000)` — yielding a per-second float
  rate.

It is used both for buckets that received measured increments and, via
`empty_value/3`, for zero-filled empty buckets (so `project(0, :rate, interval_ms)`
must yield `0.0`).

```elixir
defmodule CounterResampler do
  @moduledoc """
  Resamples readings from a monotonically increasing counter into fixed-interval
  buckets of per-interval increase (`:delta`) or per-second rate (`:rate`), with
  optional counter-reset detection.

  Because the samples are cumulative, values are derived from the *change*
  between consecutive samples. Each consecutive increment is attributed to the
  bucket of the later sample, and a bucket's value is the sum of the increments
  attributed to it.
  """

  @type datapoint :: {integer(), number()}
  @type mode :: :delta | :rate
  @type reset :: :detect | :raw
  @type fill :: :zero | nil

  @valid_mode [:delta, :rate]
  @valid_reset [:detect, :raw]
  @valid_fill [:zero, nil]

  @doc """
  Resamples cumulative counter `data` into fixed `interval_ms` buckets.

  `data` is a list of `{timestamp_ms, counter_value}` tuples at irregular
  intervals (unordered input is sorted internally). `interval_ms` is the bucket
  width in milliseconds and must be a positive integer.

  Supported `opts`:

    * `:mode` — `:delta` (default) emits the counter increase attributed to each
      bucket; `:rate` divides that increase by `interval_ms / 1000` seconds.
    * `:reset` — `:detect` (default) treats a decrease between two consecutive
      samples as a counter reset (using the later value as the increment); `:raw`
      keeps the raw difference (which may be negative).
    * `:fill` — `:zero` (default) or `:nil`, choosing how buckets with no measured
      increase are filled.

  Returns a list of `{bucket_start_ms, resampled_value}` tuples sorted ascending
  by bucket start. Empty input returns `[]`.
  """
  @spec resample([datapoint()], pos_integer(), keyword()) :: [{integer(), number() | nil}]
  def resample(data, interval_ms, opts \\ [])

  def resample([], _interval_ms, _opts), do: []

  def resample(data, interval_ms, opts)
      when is_list(data) and is_integer(interval_ms) and interval_ms > 0 do
    mode = fetch_opt!(opts, :mode, :delta, @valid_mode)
    reset = fetch_opt!(opts, :reset, :detect, @valid_reset)
    fill = fetch_opt!(opts, :fill, :zero, @valid_fill)

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

  def resample(_data, interval_ms, _opts) when not is_integer(interval_ms) do
    raise ArgumentError, "interval_ms must be a positive integer, got: #{inspect(interval_ms)}"
  end

  def resample(_data, interval_ms, _opts) when interval_ms <= 0 do
    raise ArgumentError, "interval_ms must be positive, got: #{interval_ms}"
  end

  # --------------------------------------------------------------------------
  # Private helpers
  # --------------------------------------------------------------------------

  defp increment(v0, v1, :raw), do: v1 - v0

  defp increment(v0, v1, :detect) do
    if v1 < v0, do: v1, else: v1 - v0
  end

  defp project(inc, :delta, _interval_ms) do
    # TODO
  end

  defp empty_value(_mode, _interval_ms, nil), do: nil
  defp empty_value(mode, interval_ms, :zero), do: project(0, mode, interval_ms)

  defp floor_bucket(ts, interval_ms), do: div(ts, interval_ms) * interval_ms

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