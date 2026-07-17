Implement the public `resample/3` function (the main clause that does the work, guarded by
`when is_list(data) and is_integer(interval_ms) and interval_ms > 0`).

It resamples cumulative counter `data` — a list of `{timestamp_ms, counter_value}` tuples at
irregular intervals — into fixed `interval_ms` buckets. It must:

1. Read and validate the three options with `fetch_opt!/4`, using the module's default and
   valid-value lists: `:mode` (default `:delta`, valid `@valid_mode`), `:reset` (default
   `:detect`, valid `@valid_reset`), and `:fill` (default `:zero`, valid `@valid_fill`).
2. Sort the samples ascending by timestamp (the first element of each tuple), since input may
   be unordered.
3. Determine the earliest and latest timestamps from the sorted list, and compute the
   `first_bucket` and `last_bucket` by flooring them to an `interval_ms` boundary with
   `floor_bucket/2`.
4. Compute the per-bucket increments: walk consecutive sample pairs (use
   `Enum.chunk_every(2, 1, :discard)`), compute each increment with `increment/3` (passing the
   two consecutive values and the `reset` mode), attribute it to the bucket of the **later**
   sample `t1` via `floor_bucket/2`, and **sum** increments landing in the same bucket into a
   map (use `Map.update/4`).
5. Produce every bucket from `first_bucket` to `last_bucket` inclusive, stepping by
   `interval_ms` (e.g. `Stream.iterate/2` + `Stream.take_while/2`). For each bucket, if the map
   has an increment, project it with `project/3` (mode + interval); otherwise use
   `empty_value/3` (mode + interval + fill). Emit `{bucket_start, value}` tuples in ascending
   order.

The very first sample has no predecessor, so it contributes no increment; a bucket that
receives no attributed increment gets the fill value. All the private helpers
(`increment/3`, `project/3`, `empty_value/3`, `floor_bucket/2`, `fetch_opt!/4`) already exist —
just call them.

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

  Timestamps may be negative; they are floored toward negative infinity onto the
  `interval_ms` grid.

  Arguments are always validated, even for an empty `data` list: a non-positive or
  non-integer `interval_ms`, or an option value outside the documented sets, raises
  an `ArgumentError`.

  Returns a list of `{bucket_start_ms, resampled_value}` tuples sorted ascending
  by bucket start. Empty input returns `[]`.
  """
  @spec resample([datapoint()], pos_integer(), keyword()) :: [{integer(), number() | nil}]
  def resample(data, interval_ms, opts \\ [])

  def resample(data, interval_ms, opts)
      when is_list(data) and is_integer(interval_ms) and interval_ms > 0 do
    # TODO
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