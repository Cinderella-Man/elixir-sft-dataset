defmodule EvalTask.FailureCollector do
  @moduledoc """
  ExUnit formatter that records failing tests into an ETS table so they can be
  read back after `ExUnit.run/0`. Used by the evaluator to surface per-test
  failure messages in its JSON output.
  """
  use GenServer

  @ets_table :eval_task_failures

  def start_link(_opts \\ []) do
    if :ets.whereis(@ets_table) != :undefined do
      :ets.delete(@ets_table)
    end

    :ets.new(@ets_table, [:named_table, :public, :ordered_set])
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def get_failures do
    @ets_table
    |> :ets.tab2list()
    |> Enum.map(fn {_key, failure} -> failure end)
  end

  @impl true
  def init(_), do: {:ok, 0}

  @impl true
  def handle_cast({:test_finished, %ExUnit.Test{state: nil}}, counter) do
    {:noreply, counter}
  end

  def handle_cast({:test_finished, %ExUnit.Test{} = test}, counter) do
    failure = %{
      test: to_string(test.name),
      module: inspect(test.module),
      message: format_failure(test.state)
    }

    :ets.insert(@ets_table, {counter, failure})
    {:noreply, counter + 1}
  end

  def handle_cast(_msg, counter), do: {:noreply, counter}

  @impl true
  def handle_call(:get_failures, _from, counter) do
    {:reply, get_failures(), counter}
  end

  defp format_failure({:failed, failures}) when is_list(failures) do
    failures
    |> Enum.map_join("\n", fn
      {_kind, %ExUnit.AssertionError{} = e, _stacktrace} ->
        Exception.message(e)

      {_kind, exception, _stacktrace} when is_exception(exception) ->
        Exception.message(exception)

      {kind, reason, _stacktrace} ->
        "#{inspect(kind)}: #{inspect(reason, limit: 300)}"

      other ->
        inspect(other, limit: 300)
    end)
  end

  defp format_failure({:error, {kind, reason, _stack}, _}) do
    "#{inspect(kind)}: #{inspect(reason, limit: 300)}"
  end

  defp format_failure(other), do: inspect(other, limit: 300)
end
