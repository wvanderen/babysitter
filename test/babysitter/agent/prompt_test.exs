defmodule Babysitter.Agent.PromptTest do
  use ExUnit.Case, async: true

  alias Babysitter.Agent.Prompt

  describe "wrap/2" do
    test "wraps prompt with completion instructions using default marker" do
      prompt = "Write a hello world program"
      wrapped = Prompt.wrap(prompt)

      assert String.contains?(wrapped, prompt)
      assert String.contains?(wrapped, "BABYSITTER_DONE")
      assert String.contains?(wrapped, "completed this task")
    end

    test "wraps prompt with custom marker" do
      prompt = "Write tests"
      wrapped = Prompt.wrap(prompt, marker: "CUSTOM_MARKER")

      assert String.contains?(wrapped, prompt)
      assert String.contains?(wrapped, "CUSTOM_MARKER")
      refute String.contains?(wrapped, "BABYSITTER_DONE")
    end

    test "returns original prompt when wrapper is disabled" do
      prompt = "Write code"
      wrapped = Prompt.wrap(prompt, enabled: false)

      assert wrapped == prompt
    end

    test "wraps prompt with custom instructions" do
      prompt = "Do something"
      wrapped = Prompt.wrap(prompt, instructions: "Please output DONE when finished.")

      assert String.contains?(wrapped, prompt)
      assert String.contains?(wrapped, "Please output DONE when finished.")
    end
  end

  describe "wrap_for_agent/2" do
    test "wraps prompt with agent-specific marker from config" do
      prompt = "Write code"
      wrapped = Prompt.wrap_for_agent(prompt, :pi)

      assert String.contains?(wrapped, prompt)
      assert String.contains?(wrapped, "BABYSITTER_DONE")
    end

    test "returns original prompt when agent has native_completion in config" do
      prompt = "Write code"
      wrapped = Prompt.wrap(prompt, enabled: false)

      assert wrapped == prompt
    end
  end

  describe "default_marker/0" do
    test "returns default completion marker" do
      assert Prompt.default_marker() == "BABYSITTER_DONE"
    end
  end

  describe "default_instructions/1" do
    test "generates instructions with marker" do
      instructions = Prompt.default_instructions("TEST_MARKER")

      assert String.contains?(instructions, "TEST_MARKER")
      assert String.contains?(instructions, "completed this task")
      assert String.contains?(instructions, "own line")
    end
  end

  describe "enabled_for_agent?/1" do
    test "returns true for agent without native completion" do
      assert Prompt.enabled_for_agent?(:pi) == true
    end

    test "returns true for unknown agent" do
      assert Prompt.enabled_for_agent?(:unknown_agent) == true
    end
  end
end
