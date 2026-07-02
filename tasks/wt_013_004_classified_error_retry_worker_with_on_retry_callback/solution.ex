defmodule ClassifiedRetryWorker do
  @moduledoc """
  A GenServer that executes functions with exponential backoff,
  classifying errors as transient (retryable) or permanent (non-retryable),
  with an optional on_retry callback.
  """

  use GenServer
  import Bitwise

  # --- Public API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @spec execute(GenServer.server(), (-> any()), keyword()) ::
          {:ok, any()}
          | {:error, :permanent, any()}
          | {:error, :retries_exhausted, any()}
  def execute(server, func, opts \\ []) do
    GenServer.call(server, {:execute, func, opts}, :infinity)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    random = Keyword.get(opts, :random, fn max -> :rand.uniform(max) - 1 end)
    {:ok, %{clock: clock, random: random}}
  end

  @impl true
  def handle_call({:execute, func, opts}, from, state) do
    do_execute(func, 0, opts, from, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:retry, func, attempt, opts, from}, state) do
    do_execute(func, attempt, opts, from, state)
    {:noreply, state}
  end

  # --- Private Helpers ---

  defp do_execute(func, attempt, opts, from, state) do
    max_retries = Keyword.get(opts, :max_retries, 3)

    case func.() do
      {:ok, result} ->
        GenServer.reply(from, {:ok, result})

      {:error, :permanent, reason} ->
        GenServer.reply(from, {:error, :permanent, reason})

      {:error, :transient, reason} ->
        if attempt >= max_retries do
          GenServer.reply(from, {:error, :retries_exhausted, reason})
        else
          schedule_retry(func, attempt + 1, opts, from, reason, state)
        end
    end
  end

  defp schedule_retry(func, next_attempt, opts, from, reason, state) do
    base_delay = Keyword.get(opts, :base_delay_ms, 100)
    max_delay = Keyword.get(opts, :max_delay_ms, 10_000)
    on_retry = Keyword.get(opts, :on_retry)

    n = next_attempt - 1
    shift = min(n, 50)
    delay = min(base_delay <<< shift, max_delay)

    jitter = if delay > 0, do: state.random.(delay), else: 0
    total_wait = delay + jitter

    # Invoke on_retry callback if provided
    if on_retry, do: on_retry.(next_attempt, reason, total_wait)

    Process.send_after(self(), {:retry, func, next_attempt, opts, from}, total_wait)
  end
end
