defmodule Babysitter.WorkflowTest do
  use ExUnit.Case, async: true

  alias Babysitter.Workflow

  describe "Workflow struct" do
    test "has required enforce_keys" do
      # This should compile but fail at runtime without required fields
      assert_raise ArgumentError, fn ->
        struct!(Workflow, [])
      end
    end

    test "can be created with required fields" do
      workflow = %Workflow{
        id: "test-workflow",
        name: "Test Workflow",
        stages: []
      }

      assert workflow.id == "test-workflow"
      assert workflow.name == "Test Workflow"
      assert workflow.stages == []
    end

    test "has default values for optional fields" do
      workflow = %Workflow{
        id: "test-workflow",
        name: "Test Workflow",
        stages: []
      }

      assert workflow.intelligence == :dumb
      assert workflow.transitions == nil
      assert workflow.description == nil
    end

    test "can be created with all fields" do
      workflow = %Workflow{
        id: "daily-tasks",
        name: "Daily Task Workflow",
        stages: [],
        intelligence: :hybrid,
        transitions: %{complete: %{action: :close}},
        description: "Process daily tasks"
      }

      assert workflow.id == "daily-tasks"
      assert workflow.name == "Daily Task Workflow"
      assert workflow.intelligence == :hybrid
      assert workflow.transitions == %{complete: %{action: :close}}
      assert workflow.description == "Process daily tasks"
    end
  end

  describe "intelligence type" do
    test "accepts dumb, smart, or hybrid" do
      dumb = %Workflow{id: "1", name: "Dumb", stages: [], intelligence: :dumb}
      smart = %Workflow{id: "2", name: "Smart", stages: [], intelligence: :smart}
      hybrid = %Workflow{id: "3", name: "Hybrid", stages: [], intelligence: :hybrid}

      assert dumb.intelligence == :dumb
      assert smart.intelligence == :smart
      assert hybrid.intelligence == :hybrid
    end
  end

  describe "stages field" do
    test "can contain Stage structs" do
      alias Babysitter.Stage

      stage = %Stage{
        id: :fetch,
        type: :agent,
        agent: :claude,
        prompt: "Do something"
      }

      workflow = %Workflow{
        id: "test",
        name: "Test",
        stages: [stage]
      }

      assert length(workflow.stages) == 1
      assert hd(workflow.stages).id == :fetch
    end
  end

  describe "JSON encoding" do
    test "can be encoded to JSON" do
      workflow = %Workflow{
        id: "test",
        name: "Test Workflow",
        stages: [],
        intelligence: :smart,
        description: "A test workflow"
      }

      json = Jason.encode!(workflow)
      assert is_binary(json)
      assert String.contains?(json, "test")
      assert String.contains?(json, "Test Workflow")
    end
  end

  describe "new/4 helper function" do
    test "creates workflow with required fields" do
      workflow = Workflow.new("test-id", "Test Name", [])

      assert workflow.id == "test-id"
      assert workflow.name == "Test Name"
      assert workflow.stages == []
      assert workflow.intelligence == :dumb
    end

    test "creates workflow with custom intelligence" do
      workflow = Workflow.new("test-id", "Test Name", [], intelligence: :smart)

      assert workflow.intelligence == :smart
    end

    test "creates workflow with all options" do
      workflow =
        Workflow.new("test-id", "Test Name", [],
          intelligence: :hybrid,
          transitions: %{done: %{action: :close}},
          description: "A test workflow"
        )

      assert workflow.intelligence == :hybrid
      assert workflow.transitions == %{done: %{action: :close}}
      assert workflow.description == "A test workflow"
    end
  end
end
