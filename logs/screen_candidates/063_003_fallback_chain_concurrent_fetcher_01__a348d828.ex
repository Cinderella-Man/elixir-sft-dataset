defmodule FallbackFetcher do
  @moduledoc """
  Concurrently fetches data from multiple named sources, where each source carries an
  ordered chain of fallback functions.

  Every source runs concurrently with all others. Within a source, the fallback functions
  are tried strictly in sequence: the first that returns `{:ok, value}` wins; a function
  that returns `{:error, reason}` or raises causes the next fallback to be tried. All
  sources share a single global wall-clock timeout.

  Results are returned as a map of `%{name => result_tuple}` where each result is one of:

    * `{:ok, value}` — a fallback in the chain succeeded within the timeout.
    * `{:error, {:all_failed, reasons}}` — every fallback failed; `reasons` lists the
      failure reasons in the order the functions were tried (a raised exception is captured
      as its exception struct).
    * `{:error, :timeout}` — the global timeout expired while the source was still working.

  When the timeout fires, any source still running is killed immediately, and `fetch_all/2`
  only returns once every spawned process has finished or is confirmed dead.
  """

  @typedoc "The name of a source; may be any term."
  @type name :: term()

  @typedoc "A zero-arity fallback function returning `{:ok, term}` or `{:error, term}`."
  @type fetch_fn :: (-> {:ok, term()} | {:error, term()})

  @typedoc "A single source: a name paired with its ordered chain of fallback functions."
  @type source :: {name(), [fetch_fn()]}

  @typedoc "The per-source result reported back to the caller."
  @type result ::
          {:ok, term()}
          | {:error, {:all_failed, [term()]}}
          | {:error, :timeout}

  @doc """
  Fetches from every source in `sources` concurrently under a single global `timeout_ms`
  budget, trying each source's fallback chain sequentially until one succeeds.

  Returns a map of `%{name => result}`. Returns `%{}` immediately when `sources` is empty.
  """
  @spec fetch_all([source()], non_neg_integer()) :: %{optional(name()) => result()}
  def fetch_all([], _timeout_ms), do: %{}

  def fetch_all(sources, timeout_ms) when is_list(sources) and is_integer(timeout_ms) do
    tasks = Enum.map(sources, fn {name, fns} -> {name, Task.async(fn -> run_chain(fns) end)} end)

    names = Enum.map(tasks, fn {name, _task} -> name end)
    task_list = Enum.map(tasks, fn {_name, task} -> task end)

    task_list
    |> Task.yield_many(timeout_ms)
    |> Enum.map(&resolve/1)
    |> then(&Enum.zip(names, &1))
    |> Map.new()
  end

  # Resolves a single `{task, yield_result}` pair, shutting down any task that is still
  # running so no zombie processes survive the global timeout.
  @spec resolve({Task.t(), {:ok, result()} | {:exit, term()} | nil}) :: result()
  defp resolve({task, yielded}) do
    case yielded || Task.shutdown(task, :brutal_kill) do
      {:ok, value} -> value
      _other -> {:error, :timeout}
    end
  end

  # Runs a fallback chain sequentially, accumulating failure reasons in try order.
  @spec run_chain([fetch_fn()]) :: {:ok, term()} | {:error, {:all_failed, [term()]}}
  defp run_chain(fns), do: run_chain(fns, [])

  @spec run_chain([fetch_fn()], [term()]) ::
          {:ok, term()} | {:error, {:all_failed, [term()]}}
  defp run_chain([], reasons), do: {:error, {:all_failed, Enum.reverse(reasons)}}

  defp run_chain([fun | rest], reasons) do
    case safe_call(fun) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> run_chain(rest, [reason | reasons])
    end
  end

  # Invokes a single fallback function, capturing errors, raises, throws, and exits as
  # `{:error, reason}` so the chain can continue to the next fallback.
  @spec safe_call(fetch_fn()) :: {:ok, term()} | {:error, term()}
  defp safe_call(fun) do
    try do
      case fun.() do
        {:ok, value} -> {:ok, value}
        {:error, reason} -> {:error, reason}
        other -> {:error, other}
      end
    rescue
      exception -> {:error, exception}
    catch
      :throw, value -> {:error, {:throw, value}}
      :exit, reason -> {:error, {:exit, reason}}
    end
  end
end