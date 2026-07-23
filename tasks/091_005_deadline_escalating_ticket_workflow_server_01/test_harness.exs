defmodule WorkflowServerTest do
  use ExUnit.Case, async: false

  defp notifier(pid) do
    fn {from, to, event} -> send(pid, {:wf, from, to, event}) end
  end

  # -------------------------------------------------------
  # Construction / defaults
  # -------------------------------------------------------

  test "a fresh server starts in :triage" do
    {:ok, s} = WorkflowServer.start_link([])
    assert WorkflowServer.current(s) == :triage
  end

  test "default has no deadlines: a ticket never auto-escalates on its own" do
    {:ok, s} = WorkflowServer.start_link([])
    Process.sleep(150)
    assert WorkflowServer.current(s) == :triage
  end

  # -------------------------------------------------------
  # Manual walk + allowed/2 + invalid transitions
  # -------------------------------------------------------

  test "walks triage -> closed, reporting allowed events at each step" do
    {:ok, s} = WorkflowServer.start_link([])

    assert WorkflowServer.allowed(s) == [:assign]
    assert {:error, :invalid_transition, :triage, :begin} = WorkflowServer.fire(s, :begin)
    # :timeout is reserved and cannot be fired manually
    assert {:error, :invalid_transition, :triage, :timeout} = WorkflowServer.fire(s, :timeout)

    assert {:ok, :assigned} = WorkflowServer.fire(s, :assign)
    assert WorkflowServer.allowed(s) == [:begin]

    assert {:ok, :working} = WorkflowServer.fire(s, :begin)
    assert WorkflowServer.allowed(s) == [:resolve]

    assert {:ok, :resolved} = WorkflowServer.fire(s, :resolve)
    assert WorkflowServer.allowed(s) == [:close]

    assert {:ok, :closed} = WorkflowServer.fire(s, :close)
    assert WorkflowServer.allowed(s) == []

    # terminal: nothing leaves :closed
    assert {:error, :invalid_transition, :closed, :assign} = WorkflowServer.fire(s, :assign)
    assert {:error, :invalid_transition, :closed, :begin} = WorkflowServer.fire(s, :begin)
  end

  test "unknown event is an invalid transition" do
    {:ok, s} = WorkflowServer.start_link([])
    assert {:error, :invalid_transition, :triage, :teleport} = WorkflowServer.fire(s, :teleport)
  end

  # -------------------------------------------------------
  # Automatic escalation (time model)
  # -------------------------------------------------------

  test "a stalled ticket auto-escalates when its deadline elapses" do
    {:ok, s} = WorkflowServer.start_link(deadlines: %{triage: 60}, notify: notifier(self()))

    assert_receive {:wf, :triage, :escalated, :timeout}, 1000
    assert WorkflowServer.current(s) == :escalated
    assert WorkflowServer.allowed(s) == [:assign]
  end

  test "leaving a state cancels that state's deadline (old schedule is dead)" do
    # 80ms deadline on :triage, but we leave :triage almost immediately.
    {:ok, s} = WorkflowServer.start_link(deadlines: %{triage: 80})
    assert {:ok, :assigned} = WorkflowServer.fire(s, :assign)

    # Wait well past the original triage deadline.
    Process.sleep(250)

    # If the stale triage timer had fired, we would be in :escalated.
    assert WorkflowServer.current(s) == :assigned
  end

  test "a stale deadline from a left state never escalates the current state" do
    # :triage has a short deadline; we leave :triage before it fires and land in
    # :working which has a long deadline. The old :triage timer, even if it fired
    # around the moment we left, must never escalate the ticket out of :working.
    {:ok, s} = WorkflowServer.start_link(deadlines: %{triage: 60, working: 5000})

    assert {:ok, :assigned} = WorkflowServer.fire(s, :assign)
    assert {:ok, :working} = WorkflowServer.fire(s, :begin)

    Process.sleep(200)
    assert WorkflowServer.current(s) == :working
  end

  test "entering a state arms a fresh deadline (re-entry reschedules)" do
    {:ok, s} =
      WorkflowServer.start_link(deadlines: %{triage: 60, assigned: 60}, notify: notifier(self()))

    # triage stalls -> escalated
    assert_receive {:wf, :triage, :escalated, :timeout}, 1000
    assert WorkflowServer.current(s) == :escalated

    # reassign; :assigned now arms its own fresh deadline
    assert {:ok, :assigned} = WorkflowServer.fire(s, :assign)
    assert_receive {:wf, :escalated, :assigned, :assign}, 1000

    # the new :assigned deadline fires independently
    assert_receive {:wf, :assigned, :escalated, :timeout}, 1000
    assert WorkflowServer.current(s) == :escalated
  end

  test ":escalated never arms a deadline even if present in the map" do
    {:ok, s} =
      WorkflowServer.start_link(deadlines: %{triage: 50, escalated: 50}, notify: notifier(self()))

    assert_receive {:wf, :triage, :escalated, :timeout}, 1000
    # Since :escalated is excluded, there must be no second escalation.
    Process.sleep(200)
    refute_receive {:wf, :escalated, :escalated, :timeout}, 50
    assert WorkflowServer.current(s) == :escalated
  end

  test "terminal :closed never arms a deadline even if present in the map" do
    {:ok, s} =
      WorkflowServer.start_link(deadlines: %{closed: 60}, notify: notifier(self()))

    assert {:ok, :assigned} = WorkflowServer.fire(s, :assign)
    assert {:ok, :working} = WorkflowServer.fire(s, :begin)
    assert {:ok, :resolved} = WorkflowServer.fire(s, :resolve)
    assert {:ok, :closed} = WorkflowServer.fire(s, :close)

    # drain the four manual notifications
    assert_receive {:wf, :triage, :assigned, :assign}, 1000
    assert_receive {:wf, :assigned, :working, :begin}, 1000
    assert_receive {:wf, :working, :resolved, :resolve}, 1000
    assert_receive {:wf, :resolved, :closed, :close}, 1000

    Process.sleep(150)
    refute_receive {:wf, _, :escalated, :timeout}, 50
    assert WorkflowServer.current(s) == :closed
  end

  test "automatic escalation is reported as {from_state, :escalated, :timeout}" do
    {:ok, s} = WorkflowServer.start_link(deadlines: %{triage: 40}, notify: notifier(self()))

    # The event atom must be exactly :timeout, and the from-state the state we
    # stalled in (:triage) — never a manual event atom.
    assert_receive {:wf, :triage, :escalated, :timeout}, 1000
    refute_receive {:wf, :triage, :escalated, :assign}, 50
    assert WorkflowServer.current(s) == :escalated
  end

  test "from :escalated, only :assign is valid and it re-enters :assigned" do
    {:ok, s} = WorkflowServer.start_link(deadlines: %{triage: 40})

    Process.sleep(150)
    assert WorkflowServer.current(s) == :escalated
    assert WorkflowServer.allowed(s) == [:assign]

    assert {:error, :invalid_transition, :escalated, :begin} = WorkflowServer.fire(s, :begin)
    assert {:error, :invalid_transition, :escalated, :resolve} = WorkflowServer.fire(s, :resolve)
    assert {:error, :invalid_transition, :escalated, :close} = WorkflowServer.fire(s, :close)
    assert {:error, :invalid_transition, :escalated, :timeout} = WorkflowServer.fire(s, :timeout)

    assert {:ok, :assigned} = WorkflowServer.fire(s, :assign)
    assert WorkflowServer.current(s) == :assigned
  end

  # -------------------------------------------------------
  # notify callback
  # -------------------------------------------------------

  test "notify fires once per transition with {from, to, event}" do
    {:ok, s} = WorkflowServer.start_link(notify: notifier(self()))

    assert {:ok, :assigned} = WorkflowServer.fire(s, :assign)
    assert_receive {:wf, :triage, :assigned, :assign}, 1000

    assert {:ok, :working} = WorkflowServer.fire(s, :begin)
    assert_receive {:wf, :assigned, :working, :begin}, 1000
  end

  test "notify is not invoked for a rejected manual transition" do
    {:ok, s} = WorkflowServer.start_link(notify: notifier(self()))

    # An invalid event leaves the ticket unchanged and fires no notification.
    assert {:error, :invalid_transition, :triage, :begin} = WorkflowServer.fire(s, :begin)
    refute_receive {:wf, _, _, _}, 80
    assert WorkflowServer.current(s) == :triage
  end

  test "a raising callback is isolated: transition sticks, server stays alive" do
    me = self()

    raising =
      fn {from, to, event} ->
        send(me, {:wf, from, to, event})
        raise "boom"
      end

    {:ok, s} = WorkflowServer.start_link(notify: raising)

    assert {:ok, :assigned} = WorkflowServer.fire(s, :assign)
    assert_receive {:wf, :triage, :assigned, :assign}, 1000

    # server survived the raising callback and applied the transition
    assert WorkflowServer.current(s) == :assigned

    # and it is still responsive to further calls
    assert {:ok, :working} = WorkflowServer.fire(s, :begin)
    assert_receive {:wf, :assigned, :working, :begin}, 1000
    assert WorkflowServer.current(s) == :working
  end

  test "a throwing callback is isolated just like a raising one" do
    me = self()

    throwing =
      fn {from, to, event} ->
        send(me, {:wf, from, to, event})
        throw(:nope)
      end

    {:ok, s} = WorkflowServer.start_link(notify: throwing)

    assert {:ok, :assigned} = WorkflowServer.fire(s, :assign)
    assert_receive {:wf, :triage, :assigned, :assign}, 1000

    # transition still took effect and the server is still responsive
    assert WorkflowServer.current(s) == :assigned
    assert {:ok, :working} = WorkflowServer.fire(s, :begin)
    assert WorkflowServer.current(s) == :working
  end

  # -------------------------------------------------------
  # Lifecycle
  # -------------------------------------------------------

  test "stop/1 shuts the server down" do
    {:ok, s} = WorkflowServer.start_link([])
    assert :ok = WorkflowServer.stop(s)
    refute Process.alive?(s)
  end

  test "a raising callback during an automatic timeout escalation is isolated" do
    me = self()

    raising =
      fn {from, to, event} ->
        send(me, {:wf, from, to, event})
        raise "boom"
      end

    # The isolation promise covers automatic timeout escalations, not only manual
    # transitions: the callback raises from inside the timeout-driven transition.
    {:ok, s} = WorkflowServer.start_link(deadlines: %{triage: 40}, notify: raising)

    assert_receive {:wf, :triage, :escalated, :timeout}, 1000

    # The escalation still took effect despite the callback blowing up...
    assert WorkflowServer.current(s) == :escalated
    assert WorkflowServer.allowed(s) == [:assign]

    # ...and the server is still responsive to further calls.
    assert {:ok, :assigned} = WorkflowServer.fire(s, :assign)
    assert WorkflowServer.current(s) == :assigned
  end

  test "an exiting callback is isolated like a raising or throwing one" do
    me = self()

    exiting =
      fn {from, to, event} ->
        send(me, {:wf, from, to, event})
        exit(:nope)
      end

    {:ok, s} = WorkflowServer.start_link(notify: exiting)

    assert {:ok, :assigned} = WorkflowServer.fire(s, :assign)
    assert_receive {:wf, :triage, :assigned, :assign}, 1000

    # The exit()ing callback was swallowed: transition stuck, server alive...
    assert WorkflowServer.current(s) == :assigned

    # ...and still responsive to a further call.
    assert {:ok, :working} = WorkflowServer.fire(s, :begin)
    assert WorkflowServer.current(s) == :working
  end
end
