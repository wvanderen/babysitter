defmodule Babysitter.Stage do
  @moduledoc """
  Defines a stage in a workflow pipeline.

  Each stage represents a discrete step in agent execution,
  with validation rules and transitions to subsequent stages.
  """

  @derive Jason.Encoder
  @type stage_type :: :agent | :action | :validation | :decision | :interrupt
  @type stage_id :: String.t() | atom()

  @type t :: %__MODULE__{
          id: stage_id(),
          name: String.t(),
          type: stage_type(),
          agent: atom() | nil,
          prompt: String.t() | nil,
          command: String.t() | nil,
          timeout: non_neg_integer() | :infinity,
          validations: [Babysitter.Validation.t()],
          transitions: [Babysitter.Transition.t()],
          on_success: stage_id() | nil,
          on_failure: stage_id() | nil,
          on_timeout: stage_id() | nil,
          on_approve: stage_id() | nil,
          on_deny: stage_id() | nil,
          on_modify: stage_id() | nil,
          interrupt_prompt: String.t() | nil,
          interrupt_options: [String.t()],
          metadata: map()
        }

  @enforce_keys [:id, :type]
  defstruct [
    :id,
    :type,
    :agent,
    name: nil,
    prompt: nil,
    command: nil,
    timeout: :infinity,
    validations: [],
    transitions: [],
    on_success: nil,
    on_failure: nil,
    on_timeout: nil,
    on_approve: nil,
    on_deny: nil,
    on_modify: nil,
    interrupt_prompt: nil,
    interrupt_options: [],
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
      agent: Keyword.get(opts, :agent),
      name: Keyword.get(opts, :name),
      timeout: Keyword.get(opts, :timeout, :infinity),
      validations: Keyword.get(opts, :validations, []),
      transitions: Keyword.get(opts, :transitions, []),
      on_success: Keyword.get(opts, :on_success),
      on_failure: Keyword.get(opts, :on_failure),
      on_timeout: Keyword.get(opts, :on_timeout)
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
      agent: Keyword.get(opts, :agent),
      name: Keyword.get(opts, :name),
      timeout: Keyword.get(opts, :timeout, :infinity),
      validations: Keyword.get(opts, :validations, []),
      transitions: Keyword.get(opts, :transitions, []),
      on_success: Keyword.get(opts, :on_success),
      on_failure: Keyword.get(opts, :on_failure),
      on_timeout: Keyword.get(opts, :on_timeout)
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
      on_failure: Keyword.get(opts, :on_failure),
      on_timeout: Keyword.get(opts, :on_timeout)
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
  Create an interrupt stage that pauses for human decision.

  The workflow will pause at this stage and wait for human input
  via the TUI. The user can approve, deny, or request modification.
  """
  @spec interrupt(stage_id(), String.t(), keyword()) :: t()
  def interrupt(id, prompt, opts \\ []) do
    %__MODULE__{
      id: id,
      type: :interrupt,
      interrupt_prompt: prompt,
      interrupt_options: Keyword.get(opts, :options, ["approve", "deny", "modify"]),
      name: Keyword.get(opts, :name),
      on_approve: Keyword.get(opts, :on_approve),
      on_deny: Keyword.get(opts, :on_deny),
      on_modify: Keyword.get(opts, :on_modify),
      on_success: Keyword.get(opts, :on_success),
      on_failure: Keyword.get(opts, :on_failure)
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
