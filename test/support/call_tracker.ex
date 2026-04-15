defmodule ElixirBenchmark.CallTracker do
  @moduledoc """
  Tracks function calls for assertion in tests.

  Usage:

      setup do
        {:ok, tracker} = CallTracker.start_link()
        %{tracker: tracker}
      end

      test "function called exactly once", %{tracker: tracker} do
        fun = CallTracker.track(tracker, :my_fn, fn arg -> arg * 2 end)
        assert fun.(5) == 10
        assert CallTracker.call_count(tracker, :my_fn) == 1
        assert CallTracker.calls(tracker, :my_fn) == [[5]]
      end
  """

  use Agent

  def start_link do
    Agent.start_link(fn -> %{} end)
  end

  @doc "Wraps a function so each call is recorded under `name`."
  def track(tracker, name, fun) do
    fn args ->
      Agent.update(tracker, fn state ->
        calls = Map.get(state, name, [])
        Map.put(state, name, calls ++ [args])
      end)

      apply(fun, [args])
    end
  end

  @doc "Returns a zero-arity tracked function."
  def track_fn(tracker, name, fun) do
    fn ->
      Agent.update(tracker, fn state ->
        calls = Map.get(state, name, [])
        Map.put(state, name, calls ++ [:called])
      end)

      fun.()
    end
  end

  def call_count(tracker, name) do
    Agent.get(tracker, fn state ->
      state |> Map.get(name, []) |> length()
    end)
  end

  def calls(tracker, name) do
    Agent.get(tracker, fn state ->
      Map.get(state, name, [])
    end)
  end

  def reset(tracker) do
    Agent.update(tracker, fn _ -> %{} end)
  end
end
