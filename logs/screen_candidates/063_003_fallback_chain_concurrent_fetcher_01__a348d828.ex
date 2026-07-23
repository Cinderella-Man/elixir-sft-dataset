defmodule FallbackFetcher do
  @moduledoc """
  Concurrently fetches data from multiple named sources, where each source
  carries an ordered chain of fallback functions.

  Every source runs concurrently with every other source. Within a single
  source, the fallback functions are tried sequentially, in order, until one
  returns `{:ok, value}` or the chain is exhausted. A raised exception (or a
  thrown/exited value) is treated as a failure and the next fallback is tried.

  A single global wall-clock timeout is shared across all sources. When it
  expires, any source still working through its chain is reported as
  `{:error, :timeout}` and its process is killed immediately, so no zombie
  processes remain when `fetch_all/2` returns.
  """

  @typedoc "A zero-arity fallback function."
  @type fetch_fn :: (-> {:ok, term()} | {:error, term()})

  @typedoc "A single source: a name and its ordered fallback chain."
  @type source :: {term(), [fetch_fn()]}

  @typedoc "The per-source result reported back to the caller."
  @type result ::
          {:ok, term()}
          | {:error, {:all_failed, [term()]}}
          | {:error, :timeout}

  @doc """
  Fetches all `sources` concurrently under a single global `timeout_ms` budget.

  `sources` is a list of `{name, fetch_fns}` tuples. `name` may be any term and
  `fetch_fns` is the ordered fallback chain (a list of zero-arity functions).

  Returns a map of `%{name => result_tuple}` where each value is one of:

    * `{:ok, value}` — some fallback in the chain succeeded within the timeout.
    * `{:error, {:all_failed, reasons}}` — every fallback failed; `reasons`
      lists the failure reasons in the order the functions were tried (a raised
      exception is captured as its exception struct).
    * `{:error, :timeout}` — the global timeout expired while this source was
      still working through its chain.

  Returns `%{}` immediately when `sources` is empty.
  """
  @spec fetch_all([source()], non_neg_integer()) :: %{optional(term()) => result()}
  def fetch_all([], _timeout_ms), do: %{}

  def fetch_all(sources, timeout_ms) when is_list(sources) do
    named_tasks =
      Enum.map(sources, fn {name, fetch_fns} ->
        {name, Task.async(fn -> run_chain(fetch_fns, []) end)}
      end)

    tasks = Enum.map(named_tasks, fn {_name, task} -> task end)
    yielded = Task.yield_many(tasks, timeout_ms)

    named_tasks
    |> Enum.zip(yielded)
    |> Enum.map(fn {{name, _task}, {task, outcome}} ->
      {name, resolve(task, outcome)}
    end)
    |> Map.new()
  end

  @spec resolve(Task.t(), {:ok, result()} | {:exit, term()} | nil) :: result()
  defp resolve(_task, {:ok, chain_result}), do: chain_result

  defp resolve(_task, {:exit, reason}), do: {:error, {:all_failed, [{:exit, reason}]}}

  defp resolve(task, nil) do
    _ = Task.shutdown(task, :brutal_kill)
    {:error, :timeout}
  end

  @spec run_chain([fetch_fn()], [term()]) :: result()
  defp run_chain([], reasons), do: {:error, {:all_failed, Enum.reverse(reasons)}}

  defp run_chain([fun | rest], reasons) do
    case attempt(fun) do
      {:ok, value} -> {:ok, value}
      {:failed, reason} -> run_chain(rest, [reason | reasons])
    end
  end

  @spec attempt(fetch_fn()) :: {:ok, term()} | {:failed, term()}
  defp attempt(fun) do
    try do
      case fun.() do
        {:ok, value} -> {:ok, value}
        {:error, reason} -> {:failed, reason}
        other -> {:failed, {:unexpected_return, other}}
      end
    rescue
      exception -> {:failed, exception}
    catch
      kind, value -> {:failed, {kind, value}}
    end
  end
end