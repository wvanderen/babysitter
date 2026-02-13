defmodule Babysitter.StageTest do
  use ExUnit.Case, async: true

  alias Babysitter.{Stage, Validation, Transition}

  describe "agent/3" do
    test "creates an agent stage with prompt" do
      stage = Stage.agent(:analyze, "Analyze the code", name: "Code Analysis")

      assert stage.id == :analyze
      assert stage.type == :agent
      assert stage.prompt == "Analyze the code"
      assert stage.name == "Code Analysis"
    end
  end

  describe "action/3" do
    test "creates an action stage with command" do
      stage = Stage.action(:build, "mix compile", timeout: 30_000)

      assert stage.id == :build
      assert stage.type == :action
      assert stage.command == "mix compile"
      assert stage.timeout == 30_000
    end
  end

  describe "validation/3" do
    test "creates a validation stage" do
      valid = Validation.output_contains("success")
      stage = Stage.validation(:check, [valid])

      assert stage.id == :check
      assert stage.type == :validation
      assert length(stage.validations) == 1
    end
  end

  describe "decision/3" do
    test "creates a decision stage with transitions" do
      t1 = Transition.on_success(:next)
      t2 = Transition.on_failure(:retry)
      stage = Stage.decision(:branch, [t1, t2])

      assert stage.id == :branch
      assert stage.type == :decision
      assert length(stage.transitions) == 2
    end
  end

  describe "add_validation/2" do
    test "adds validation to stage" do
      stage =
        Stage.agent(:test, "prompt")
        |> Stage.add_validation(Validation.exit_code(0))

      assert length(stage.validations) == 1
    end
  end

  describe "add_transition/2" do
    test "adds transition to stage" do
      stage =
        Stage.action(:run, "cmd")
        |> Stage.add_transition(Transition.on_success(:next))

      assert length(stage.transitions) == 1
    end
  end
end
