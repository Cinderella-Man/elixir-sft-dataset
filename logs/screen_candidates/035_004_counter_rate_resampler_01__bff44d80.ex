defmodule CounterResampler do
  @moduledoc """
  Resamples readings from a monotonically increasing counter (Prometheus-style)
  into fixed-interval buckets of per-interval increase or per-second rate.

  Because a counter is cumulative, the meaningful signal is the *change* between
  consecutive samples rather than the sample values themselves. This module

    * sorts samples ascending by timestamp,
    * computes the increment between each pair of consecutive samples (optionally
      detecting counter resets, where a decrease is treated as the value
      accumulated since the reset),
    * attributes each increment to the fixed-width bucket of the later sample, and
    * emits one `{bucket_start_ms, value}` tuple per bucket in the covered range.

  See `resample/3` for the full option set and semantics.
  """

  @modes [:delta, :rate]
  @resets [:detect, :raw]
  @fills [:zero, nil]

  @typedoc "A single counter reading: `{timestamp_ms, counter_value}`."
  @type sample :: {integer(), number()}

  @typedoc "A resampled bucket: `{bucket_start_ms, value}`."
  @type bucket :: {integer(), number() | nil}

  @doc """
  Resamples `data` into fixed `interval_ms`-wide buckets.

  `data` is a list of `{timestamp_ms, counter_value}` tuples at irregular
  intervals (input may be unordered). `interval_ms` is the bucket width in
  milliseconds and must be a positive integer.

  ## Options

    * `:mode` — `:delta` (default) emits the total counter increase attributed to
      the bucket; `:rate` emits that increase divided by the interval length in
      seconds (`interval_ms / 1000`), yielding a per-second float.
    * `:reset` — `:detect` (default) treats a decrease between consecutive samples
      `(t0, v0) -> (t1, v1)` as a reset, contributing `v1`; `:raw` always
      contributes `v1 - v0` (possibly negative).
    * `:fill` — `:zero` (default) or `nil`. Value used for buckets that receive no
      attributed increment (`0`/`nil` for `:delta`, `0.0`/`nil` for `:rate`).

  Returns a list of `{bucket_start_ms, value}` tuples sorted ascending by bucket
  start. Raises `ArgumentError` on an invalid `interval_ms` or option value.

  ## Examples

      iex> CounterResampler.resample([{0, 0}, {1000, 5}], 1000, [])
      [{0, 0}, {1000, 5}]

  """
  @spec resample([sample()], pos_integer(), keyword()) :: [bucket()]
  def resample(data, interval_ms, opts) when is_list(data) and is_list(opts) do
    unless is_integer(interval_ms) and interval_ms > 0 do
      raise ArgumentError,
            "interval_ms must be a positive integer, got: #{inspect(interval_ms)}"
    end

    mode = validate(Keyword.get(opts, :mode, :delta), @modes, :mode)
    reset = validate(Keyword.get(opts, :reset, :detect), @resets, :reset)
    fill = validate(Keyword.get(opts, :fill, :zero), @fills, :fill)

    do_resample(data, interval_ms, mode, reset, fill)
  end

  @spec do_resample([sample()], pos_integer(), atom(), atom(), atom()) :: [bucket()]
  defp do_resample([], _interval_ms, _mode, _reset, _fill), do: []

  defp do_resample(data, interval_ms, mode, reset, fill) do
    sorted = Enum.sort_by(data, fn {t, _v} -> t end)
    increments = accumulate(sorted, interval_ms, reset)

    first_t = sorted |> hd() |> elem(0)
    last_t = sorted |> List.last() |> elem(0)
    first_bucket = bucket_start(first_t, interval_ms)
    last_bucket = bucket_start(last_t, interval_ms)

    first_bucket
    |> Stream.iterate(&(&1 + interval_ms))
    |> Enum.take_while(&(&1 <= last_bucket))
    |> Enum.map(fn b ->
      {b, value_for(b, increments, mode, fill, interval_ms)}
    end)
  end

  @spec accumulate([sample()], pos_integer(), atom()) :: %{integer() => number()}
  defp accumulate(sorted, interval_ms, reset) do
    sorted
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(%{}, fn [{_t0, v0}, {t1, v1}], acc ->
      inc = increment(v0, v1, reset)
      bucket = bucket_start(t1, interval_ms)
      Map.update(acc, bucket, inc, &(&1 + inc))
    end)
  end

  @spec increment(number(), number(), atom()) :: number()
  defp increment(v0, v1, :detect) do
    if v1 >= v0, do: v1 - v0, else: v1
  end

  defp increment(v0, v1, :raw), do: v1 - v0

  @spec bucket_start(integer(), pos_integer()) :: integer()
  defp bucket_start(t, interval_ms) do
    Integer.floor_div(t, interval_ms) * interval_ms
  end

  @spec value_for(integer(), %{integer() => number()}, atom(), atom(), pos_integer()) ::
          number() | nil
  defp value_for(bucket, increments, mode, fill, interval_ms) do
    case Map.fetch(increments, bucket) do
      {:ok, sum} -> present_value(sum, mode, interval_ms)
      :error -> fill_value(mode, fill)
    end
  end

  @spec present_value(number(), atom(), pos_integer()) :: number()
  defp present_value(sum, :delta, _interval_ms), do: sum
  defp present_value(sum, :rate, interval_ms), do: sum / (interval_ms / 1000)

  @spec fill_value(atom(), atom()) :: number() | nil
  defp fill_value(:delta, :zero), do: 0
  defp fill_value(:rate, :zero), do: +0.0
  defp fill_value(_mode, _fill), do: nil

  @spec validate(term(), [term()], atom()) :: term()
  defp validate(value, allowed, name) do
    if value in allowed do
      value
    else
      raise ArgumentError,
            "invalid #{name} #{inspect(value)}, expected one of #{inspect(allowed)}"
    end
  end
end