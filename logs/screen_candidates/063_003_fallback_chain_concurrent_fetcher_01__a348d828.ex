defmodule FallbackFetcher do
  @moduledoc """
  Concurrently fetches data from multiple named sources, where each source carries an
  ordered chain of fallback functions.

  Every source is run in its own process, so sources make progress independently of one
  another. Within a single source the fallback functions are tried strictly sequentially:
  the first function is invoked, and only if it fails (by returning `{:error, reason}` or
  by raising) is the next one tried, and so on until one succeeds or the chain runs out.

  A single global wall-clock budget (`timeout_ms`) is shared by every source. It is *not*
  a per-source or per-fallback budget: a source whose chain, summed sequentially, overruns
  the deadline is reported as `{:error, :timeout}` and its process is killed immediately,
  leaving no zombies behind.

  ## Result shape

  `fetch_all/2` returns a map of `%{name => result}` where `result` is one of:

    * `{:ok, value}` — some fallback in the chain succeeded before the deadline;
    * `{:error, {:all_failed, reasons}}` — every fallback failed; `reasons` lists the
      failure reasons in the order the functions were tried (a raised exception is
      captured as its exception struct);
    * `{:error, :timeout}` — the global deadline expired while the source was still
      working through its chain.

  ## Example

      iex> sources = [
      ...>   {:primary, [fn -> {:error, :down} end, fn -> {:ok, 42} end]},
      ...>   {:secondary, [fn -> {:error, :nope} end]}
      ...> ]
      iex> FallbackFetcher.fetch_all(sources, 1_000)
      %{primary: {:ok, 42}, secondary: {:error, {:all_failed, [:nope]}}}
  """

  @typedoc "A zero-arity fallback function returning `{:ok, term}` or `{:error, term}`."
  @type fetch_fun :: (-> {:ok, term()} | {:error, term()})

  @typedoc "A source: an arbitrary name paired with its ordered fallback chain."
  @type source :: {term(), [fetch_fun()]}

  @typedoc "The outcome recorded for a single source."
  @type result :: {:ok, term()} | {:error, {:all_failed, [term()]}} | {:error, :timeout}

  @doc """
  Fetches every source concurrently under a single shared `timeout_ms` budget.

  Each `{name, fetch_fns}` entry in `sources` is executed in its own task, started
  immediately. Inside a task the functions in `fetch_fns` are tried in order until one
  returns `{:ok, value}`; failures (`{:error, reason}` or a raise) move on to the next
  function. Exits and throws inside a fallback are also treated as failures and recorded
  as `{:exit, reason}` / `{:throw, value}` respectively.

  Returns a map of `%{name => t:result/0}`. Duplicate names collapse, with the later
  source in the list winning. An empty `sources` list returns `%{}` without waiting.

  ## Examples

      iex> FallbackFetcher.fetch_all([], 100)
      %{}

      iex> FallbackFetcher.fetch_all([{"a", [fn -> raise "boom" end]}], 100)
      %{"a" => {:error, {:all_failed, [%RuntimeError{message: "boom"}]}}}
  """
  @spec fetch_all([source()], timeout()) :: %{optional(term()) => result()}
  def fetch_all([], _timeout_ms), do: %{}

  def fetch_all(sources, timeout_ms) when is_list(sources) do
    tasks = Enum.map(sources, &start_source/1)

    tasks
    |> await_tasks(timeout_ms)
    |> Map.new()
  end

  # Spawns one unlinked, monitored task per source and remembers the source name.
  @spec start_source(source()) :: {term(), Task.t()}
  defp start_source({name, fetch_fns}) when is_list(fetch_fns) do
    task =
      Task.Supervisor.async_nolink(
        FallbackFetcher.TaskSupervisor,
        fn -> run_chain(fetch_fns, []) end
      )

    {name, task}
  end

  # Collects results under the shared deadline, then shuts down whatever is still running.
  @spec await_tasks([{term(), Task.t()}], timeout()) :: [{term(), result()}]
  defp await_tasks(tasks, timeout_ms) do
    tasks
    |> Enum.map(fn {_name, task} -> task end)
    |> Task.yield_many(timeout_ms)
    |> Enum.zip(tasks)
    |> Enum.map(fn {{_task, outcome}, {name, task}} ->
      {name, resolve(outcome, task)}
    end)
  end

  # Turns a `Task.yield_many/2` outcome into the public result tuple, killing stragglers.
  @spec resolve({:ok, term()} | {:exit, term()} | nil, Task.t()) :: result()
  defp resolve({:ok, result}, _task), do: result
  defp resolve({:exit, reason}, _task), do: {:error, {:all_failed, [{:exit, reason}]}}

  defp resolve(nil, task) do
    case Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _other -> {:error, :timeout}
    end
  end

  # Tries the fallbacks in order, accumulating failure reasons (reversed) as it goes.
  @spec run_chain([fetch_fun()], [term()]) :: result()
  defp run_chain([], reasons), do: {:error, {:all_failed, Enum.reverse(reasons)}}

  defp run_chain([fetch_fun | rest], reasons) do
    case safe_call(fetch_fun) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> run_chain(rest, [reason | reasons])
    end
  end

  # Invokes a single fallback, converting raises/throws/exits into `{:error, reason}`.
  @spec safe_call(fetch_fun()) :: {:ok, term()} | {:error, term()}
  defp safe_call(fetch_fun) do
    case fetch_fun.() do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:bad_return, other}}
    end
  rescue
    exception -> {:error, exception}
  catch
    :throw, value -> {:error, {:throw, value}}
    :exit, reason -> {:error, {:exit, reason}}
  end
end

defmodule FallbackFetcher.Application do
  @moduledoc """
  Supervision tree owning the `Task.Supervisor` that `FallbackFetcher` spawns source
  tasks under.

  Running the tasks under a supervisor (rather than bare `Task.async/1`) guarantees that
  a killed or crashed source can never leak: the supervisor is the parent, it cleans up
  children, and `Task.Supervisor.async_nolink/2` keeps a failing source from taking the
  caller down with it.
  """

  use Application

  @doc """
  Starts the supervision tree, booting the task supervisor used by `FallbackFetcher`.
  """
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: FallbackFetcher.TaskSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: FallbackFetcher.Supervisor)
  end
end