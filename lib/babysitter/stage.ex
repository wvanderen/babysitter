defmodule Babysitter.Stage do
  @moduledoc """
  Defines a stage in a workflow pipeline.

  Each stage represents a discrete step in agent execution,
  with validation rules and transitions to subsequent stages.
  """

  @type stage_type :: :agent | :action | :validation | :decision
  @type stage_id :: String.t() | atom()

  @type t :: %__MODULE__{
          id: stage_id(),
          name: String.t(),
          type: stage_type(),
          prompt: String.t() | nil,
          command: String.t() | nil,
          timeout: non_neg_integer() | :infinity,
          validations: [Babysitter.Validation.t()],
          transitions: [Babysitter.Transition.t()],
          on_success: stage_id() | nil,
          on_failure: stage_id() | nil,
          metadata: map()
        }

  @enforce_keys [:id, :type]
  defstruct [
    :id,
    :type,
    name: nil,
    prompt: nil,
    command: nil,
    timeout: :infinity,
    validations: [],
    transitions: [],
    on_success: nil,
    on_failure: nil,
    metadata: %{}
  ]

  @doc """
  Create a new agent stage.
  """
  @spec agent(stage_id(), String.t(), keyword()) :: t()
  def agent(id, prompt, opts \\ []) do
    %__MODULE__{
      id: id,
      type: :agent,
      prompt: prompt,
      name: Keyword.get(opts, :name),
      timeout: Keyword.get(opts, :timeout, :infinity),
      validations: Keyword.get(opts, :validations, []),
      on_success: Keyword.get(opts, :on_success),
      on_failure: Keyword.get(opts, :on_failure)
    }
  end

  @doc """
  Create a new action stage (shell command).
  """
  @spec action(stage_id(), String.t(), keyword()) :: t()
  def action(id, command, opts \\ []) do
    %__MODULE__{
      id: id,
      type: :action,
      command: command,
      name: Keyword.get(opts, :name),
      timeout: Keyword.get(opts, :timeout, :infinity),
      validations: Keyword.get(opts, :validations, []),
      on_success: Keyword.get(opts, :on_success),
      on_failure: Keyword.get(opts, :on_failure)
    }
  end

  @doc """
  Create a validation stage.
  """
  @spec validation(stage_id(), [Babysitter.Validation.t()], keyword()) :: t()
  def validation(id, validations, opts \\ []) do
    %__MODULE__{
      id: id,
      type: :validation,
      validations: validations,
      name: Keyword.get(opts, :name),
      on_success: Keyword.get(opts, :on_success),
      on_failure: Keyword.get(opts, :on_failure)
    }
  end

  @doc """
  Create a decision stage with conditional transitions.
  """
  @spec decision(stage_id(), [Babysitter.Transition.t()], keyword()) :: t()
  def decision(id, transitions, opts \\ []) do
    %__MODULE__{
      id: id,
      type: :decision,
      transitions: transitions,
      name: Keyword.get(opts, :name)
    }
  end

  @doc """
  Add a validation to a stage.
  """
  @spec add_validation(t(), Babysitter.Validation.t()) :: t()
  def add_validation(%__MODULE__{} = stage, %Babysitter.Validation{} = validation) do
    %{stage | validations: stage.validations ++ [validation]}
  end

  @doc """
  Add a transition to a stage.
  """
  @spec add_transition(t(), Babysitter.Transition.t()) :: t()
  def add_transition(%__MODULE__{} = stage, %Babysitter.Transition{} = transition) do
    %{stage | transitions: stage.transitions ++ [transition]}
  end
end
