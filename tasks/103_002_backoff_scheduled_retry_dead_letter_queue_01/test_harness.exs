defmodule BackoffDLQTest do
  use ExUnit.Case, async: false

  defmodule Clock do
    use Agent
    def start_link(initial \\ 0), do: Agent.start_link(fn -> initial end, name: __MODULE__)
    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} =
      BackoffDLQ.start_link(clock: &Clock.now/0, base_backoff_ms: 1000, max_attempts: 3)

    %{dlq: pid}
  end

  test "push stores a pending, immediately-ready message", %{dlq: dlq} do
    assert {:ok, id} = BackoffDLQ.push(dlq, "q", %{n: 1}, :timeout, %{src: "web"})
    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.id == id
    assert e.retry_count == 0
    assert e.status == :pending
    assert e.next_retry_at == 0
    assert [r] = BackoffDLQ.ready(dlq, "q", 10)
    assert r.id == id
  end

  test "peek on unknown queue returns []", %{dlq: dlq} do
    assert BackoffDLQ.peek(dlq, "nope", 10) == []
  end

  test "success removes the message", %{dlq: dlq} do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :boom, %{})
    assert :ok = BackoffDLQ.retry(dlq, "q", id, fn _ -> :ok end)
    assert BackoffDLQ.peek(dlq, "q", 10) == []
  end

  test "failure bumps retry_count and schedules exponential backoff", %{dlq: dlq} do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})

    assert {:error, :boom} = BackoffDLQ.retry(dlq, "q", id, fn _ -> {:error, :boom} end)
    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
    assert e.next_retry_at == 1000

    Clock.advance(1000)
    assert {:error, :boom} = BackoffDLQ.retry(dlq, "q", id, fn _ -> {:error, :boom} end)
    assert [e2] = BackoffDLQ.peek(dlq, "q", 10)
    assert e2.retry_count == 2
    assert e2.next_retry_at == 3000
  end

  test "retry before next_retry_at is rejected as :not_ready without running the handler", %{
    dlq: dlq
  } do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})
    assert {:error, :boom} = BackoffDLQ.retry(dlq, "q", id, fn _ -> {:error, :boom} end)

    # now still 0, next_retry_at == 1000
    assert {:error, :not_ready, 1000} = BackoffDLQ.retry(dlq, "q", id, fn _ -> :ok end)
    # unchanged retry_count proves the handler did not run
    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
  end

  test "ready/3 excludes not-yet-due messages and includes them after the backoff elapses", %{
    dlq: dlq
  } do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})
    assert {:error, :boom} = BackoffDLQ.retry(dlq, "q", id, fn _ -> {:error, :boom} end)

    assert BackoffDLQ.ready(dlq, "q", 10) == []
    Clock.advance(1000)
    assert [r] = BackoffDLQ.ready(dlq, "q", 10)
    assert r.id == id
  end

  test "message becomes :dead after max_attempts failures and is no longer retryable", %{dlq: dlq} do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})

    fail = fn _ -> {:error, :again} end
    # rc 1, due 1000
    assert {:error, :again} = BackoffDLQ.retry(dlq, "q", id, fail)
    Clock.advance(1000)
    # rc 2, due 3000
    assert {:error, :again} = BackoffDLQ.retry(dlq, "q", id, fail)
    Clock.advance(2000)
    # rc 3 -> dead
    assert {:error, :again} = BackoffDLQ.retry(dlq, "q", id, fail)

    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.status == :dead
    assert e.retry_count == 3

    assert {:error, :dead} = BackoffDLQ.retry(dlq, "q", id, fn _ -> :ok end)
    assert BackoffDLQ.ready(dlq, "q", 10) == []
  end

  test "a raising handler counts as failure and does not crash the process", %{dlq: dlq} do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})
    assert {:error, _} = BackoffDLQ.retry(dlq, "q", id, fn _ -> raise "kaboom" end)
    assert Process.alive?(dlq)
    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
  end

  test "retry on unknown id returns :not_found", %{dlq: dlq} do
    assert {:error, :not_found} = BackoffDLQ.retry(dlq, "q", 999, fn _ -> :ok end)
    assert {:error, :not_found} = BackoffDLQ.retry(dlq, "missing", 0, fn _ -> :ok end)
  end

  test "purge removes by age regardless of status", %{dlq: dlq} do
    {:ok, _} = BackoffDLQ.push(dlq, "q", :old, :err, %{})
    Clock.advance(1000)
    {:ok, b} = BackoffDLQ.push(dlq, "q", :new, :err, %{})

    assert {:ok, 1} = BackoffDLQ.purge(dlq, "q", 500)
    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.id == b
  end

  test "queues are independent", %{dlq: dlq} do
    {:ok, a} = BackoffDLQ.push(dlq, "a", :ma, :err, %{})
    {:ok, _} = BackoffDLQ.push(dlq, "b", :mb, :err, %{})

    assert {:error, :x} = BackoffDLQ.retry(dlq, "a", a, fn _ -> {:error, :x} end)
    assert [ea] = BackoffDLQ.peek(dlq, "a", 10)
    assert ea.retry_count == 1
    assert [eb] = BackoffDLQ.peek(dlq, "b", 10)
    assert eb.retry_count == 0
  end
end
