Implement the `handle_call/3` GenServer callback for `CusumAnomaly`. It must handle
three request shapes. Implement it one clause at a time.

**`{:push, name, value}`** — process a value against the named stream. First fetch the
stream state (defaulting to a fresh zeroed stream via `stream_for/2`) and coerce
`value` to a float. Then decide, in order:

  1. If the stream carries an `:alerted` flag (it fired an alert and is frozen until
     an explicit reset), do not touch it — just reply `:warming_up`.
  2. If the stream is still warming up (`samples < warmup_samples`), update Welford
     only via `welford_update/2`, store it, and reply `:warming_up` (no CUSUM yet).
  3. If the stream is CUSUM-active but its current stddev is below `slack`
     (`welford_stddev(stream) < state.slack`), z-scoring is meaningless — just update
     Welford, store it, and reply `:ok`.
  4. Otherwise run the CUSUM step: z-score `value` against the **prior** mean and
     stddev (`z = (value - prior_mean) / max(welford_stddev(stream), epsilon)`),
     update both cumulative sums
     (`s_high = max(0.0, s_high + z - slack)`, `s_low = max(0.0, s_low - z - slack)`),
     then update Welford with `value` (always after z-scoring) and graft the new
     `s_high`/`s_low` onto the post-Welford stream. If `new_s_high >= threshold`, reply
     `{:alert, :upward_shift}` and store a fresh `alerted_stream()`. Else if
     `new_s_low >= threshold`, reply `{:alert, :downward_shift}` and store a fresh
     `alerted_stream()`. Otherwise reply `:ok` and store the updated stream.

**`{:check, name}`** — look the stream up in `state.streams`. If absent, reply
`{:error, :no_data}`. Otherwise build a status map with `mean`, `stddev`
(via `welford_stddev/1`), `s_high`, `s_low`, `samples`, and `status` (`:warming_up`
if `samples < warmup_samples`, else `:normal`) and reply `{:ok, info}`.

**`{:reset, name}`** — if the stream exists, replace it with `reset_stream()`;
otherwise leave `state.streams` untouched (do not create a stream). Reply `:ok`.

In every case return the appropriate `{:reply, reply, new_state}` tuple, using the
`put_stream/3` helper to write stream state back.

```elixir
defmodule CusumAnomaly do
  @moduledoc """
  A GenServer that maintains multiple named numeric streams and detects
  change-points via a two-sided CUSUM algorithm backed by Welford's online
  mean/variance.

  On each push of `x`:

    1. If `samples < warmup_samples`, push to Welford and return `:warming_up`.
    2. Otherwise, z-score `x` against the **prior** mean/stddev:
         z = (x - mean) / max(stddev, epsilon)
    3. Update CUSUMs:
         s_high = max(0.0, s_high + z - slack)
         s_low  = max(0.0, s_low  - z - slack)
    4. Update Welford with `x`.
    5. If `s_high >= threshold`, emit `:upward_shift` and reset ALL state
       (Welford + both CUSUMs) so the detector re-learns the new regime.
    6. Likewise for `s_low >= threshold` → `:downward_shift` + reset.

  State per stream:

      %{
        samples:  non_neg_integer,
        mean:     float,
        m2:       float,             # Welford's sum of squared differences
        s_high:   float,
        s_low:    float
      }

  Global config (not per stream):

      %{threshold, slack, warmup_samples, epsilon}

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 5.0) * 1.0
    slack = Keyword.get(opts, :slack, 0.5) * 1.0
    warmup = Keyword.get(opts, :warmup_samples, 10)
    epsilon = Keyword.get(opts, :epsilon, 1.0e-6) * 1.0

    validate!(threshold, slack, warmup, epsilon)

    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @spec push(GenServer.server(), term(), number()) ::
          :ok | :warming_up | {:alert, :upward_shift | :downward_shift}
  def push(server, name, value) when is_number(value) do
    GenServer.call(server, {:push, name, value})
  end

  @spec check(GenServer.server(), term()) ::
          {:ok, map()} | {:error, :no_data}
  def check(server, name), do: GenServer.call(server, {:check, name})

  @spec reset(GenServer.server(), term()) :: :ok
  def reset(server, name), do: GenServer.call(server, {:reset, name})

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    threshold = Keyword.get(opts, :threshold, 5.0) * 1.0
    slack = Keyword.get(opts, :slack, 0.5) * 1.0
    warmup = Keyword.get(opts, :warmup_samples, 10)
    epsilon = Keyword.get(opts, :epsilon, 1.0e-6) * 1.0

    {:ok,
     %{
       streams: %{},
       threshold: threshold,
       slack: slack,
       warmup_samples: warmup,
       epsilon: epsilon
     }}
  end

  @impl GenServer
  def handle_call(request, _from, state) do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # Welford's online mean and variance
  # ---------------------------------------------------------------------------

  defp welford_update(stream, value) do
    n = stream.samples + 1
    delta = value - stream.mean
    new_mean = stream.mean + delta / n
    delta2 = value - new_mean
    new_m2 = stream.m2 + delta * delta2
    %{stream | samples: n, mean: new_mean, m2: new_m2}
  end

  defp welford_stddev(%{samples: 0}), do: 0.0
  defp welford_stddev(%{samples: n, m2: m2}), do: :math.sqrt(m2 / n)

  # ---------------------------------------------------------------------------
  # Stream helpers
  # ---------------------------------------------------------------------------

  defp stream_for(state, name), do: Map.get(state.streams, name, reset_stream())

  defp put_stream(state, name, stream),
    do: %{state | streams: Map.put(state.streams, name, stream)}

  defp reset_stream do
    %{samples: 0, mean: 0.0, m2: 0.0, s_high: 0.0, s_low: 0.0}
  end

  defp alerted_stream do
    %{samples: 0, mean: 0.0, m2: 0.0, s_high: 0.0, s_low: 0.0, alerted: true}
  end

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

  defp validate!(threshold, slack, warmup, epsilon) do
    if threshold <= 0.0, do: raise(ArgumentError, ":threshold must be positive")
    if slack < 0.0, do: raise(ArgumentError, ":slack must be non-negative")

    unless is_integer(warmup) and warmup > 0,
      do: raise(ArgumentError, ":warmup_samples must be a positive integer")

    if epsilon <= 0.0, do: raise(ArgumentError, ":epsilon must be positive")
  end
end
```