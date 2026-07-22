defmodule AssertHelpersTest do
  use ExUnit.Case, async: false
  use AssertHelpers

  describe "assert_next_message/2" do
    test "passes when the expected message is the next one" do
      send(self(), {:hello, 1})
      assert_next_message({:hello, 1})
    end

    test "passes when the message arrives slightly later" do
      parent = self()

      spawn(fn ->
        Process.sleep(20)
        send(parent, :ping)
      end)

      assert_next_message(:ping, 500)
    end

    test "fails when a different message arrives" do
      send(self(), :unexpected)

      result =
        try do
          assert_next_message(:wanted)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "unexpected"
      assert result =~ "wanted"
    end

    test "fails when no message arrives before the timeout" do
      result =
        try do
          assert_next_message(:never, 50)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "timed out" or result =~ "50"
    end
  end

  describe "assert_no_message/1" do
    test "passes when the mailbox stays empty" do
      assert_no_message(50)
    end

    test "fails when a message arrives within the window" do
      send(self(), :surprise)

      result =
        try do
          assert_no_message(50)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "surprise"
    end
  end

  describe "assert_process_exits/2" do
    test "passes when the process terminates in time" do
      pid = spawn(fn -> Process.sleep(20) end)
      assert_process_exits(pid, 500)
    end

    test "passes immediately for an already-dead process" do
      pid = spawn(fn -> :ok end)
      Process.sleep(20)
      refute Process.alive?(pid)
      assert_process_exits(pid, 200)
    end

    test "fails when the process outlives the timeout" do
      pid = spawn(fn -> Process.sleep(1_000) end)

      result =
        try do
          assert_process_exits(pid, 50)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "did not terminate" or result =~ "50"

      Process.exit(pid, :kill)
    end

    test "does not leave a stray :DOWN message after a timeout" do
      pid = spawn(fn -> Process.sleep(1_000) end)

      _ =
        try do
          assert_process_exits(pid, 50)
        rescue
          _ -> :ok
        end

      Process.exit(pid, :kill)

      # The monitor should have been flushed, so no :DOWN is waiting.
      assert_no_message(80)
    end
  end
end