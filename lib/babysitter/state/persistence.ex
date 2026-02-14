defmodule Babysitter.State.Persistence do
  @moduledoc """
  API for persisting and recovering session state across daemon restarts.
  """

  alias Babysitter.State.{Repo, SessionState}

  @doc """
  Save session state to the database.
  Creates a new record or updates existing.
  """
  @spec save_session(map()) :: {:ok, SessionState.t()} | {:error, Ecto.Changeset.t()}
  def save_session(%{id: id} = session) do
    attrs = session_to_attrs(session)

    case Repo.get(SessionState, id) do
      nil ->
        %SessionState{id: id}
        |> Ecto.Changeset.change(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> Ecto.Changeset.change(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Load session state from the database.
  """
  @spec load_session(String.t()) :: {:ok, SessionState.t()} | {:error, :not_found}
  def load_session(id) do
    case Repo.get(SessionState, id) do
      nil -> {:error, :not_found}
      state -> {:ok, state}
    end
  end

  @doc """
  Delete session state from the database.
  """
  @spec delete_session(String.t()) :: {:ok, SessionState.t()} | {:error, :not_found}
  def delete_session(id) do
    case Repo.get(SessionState, id) do
      nil -> {:error, :not_found}
      state -> Repo.delete(state)
    end
  end

  @doc """
  List all session states matching optional filters.
  """
  @spec list_sessions(keyword()) :: [SessionState.t()]
  def list_sessions(opts \\ []) do
    import Ecto.Query

    status = Keyword.get(opts, :status)

    query = from(s in SessionState, order_by: [desc: s.updated_at])

    query =
      if status do
        where(query, [s], s.status == ^status)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  List sessions that can be recovered (not stopped/completed).
  """
  @spec recoverable_sessions() :: [SessionState.t()]
  def recoverable_sessions do
    import Ecto.Query

    from(s in SessionState,
      where: s.status not in ["stopped", "completed"],
      order_by: [desc: s.updated_at]
    )
    |> Repo.all()
  end

  @doc """
  Update session status.
  """
  @spec update_status(String.t(), String.t()) ::
          {:ok, SessionState.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_status(id, new_status) do
    case Repo.get(SessionState, id) do
      nil ->
        {:error, :not_found}

      state ->
        state
        |> Ecto.Changeset.change(%{status: new_status})
        |> Repo.update()
    end
  end

  @doc """
  Append output to session buffer.
  """
  @spec append_output(String.t(), String.t()) ::
          {:ok, SessionState.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def append_output(id, output) do
    case Repo.get(SessionState, id) do
      nil ->
        {:error, :not_found}

      state ->
        new_buffer = (state.output_buffer || "") <> output

        max_size = 100_000

        new_buffer =
          if byte_size(new_buffer) > max_size do
            drop_bytes = byte_size(new_buffer) - max_size
            binary_part(new_buffer, drop_bytes, max_size)
          else
            new_buffer
          end

        state
        |> Ecto.Changeset.change(%{output_buffer: new_buffer})
        |> Repo.update()
    end
  end

  @doc """
  Check if a session exists in persistence.
  """
  @spec exists?(String.t()) :: boolean()
  def exists?(id) do
    Repo.get(SessionState, id) != nil
  end

  defp session_to_attrs(session) do
    %{
      status: to_string(session[:status] || "initializing"),
      tmux_name: session[:tmux_name],
      started_at: session[:started_at] |> to_naive_datetime(),
      output_buffer: session[:output_buffer] || "",
      metadata: session[:metadata] || %{},
      failure_reason: session[:failure_reason],
      escalation_reason: session[:escalation_reason],
      validation_results: serialize_validation_results(session[:validation_results]),
      session_data: session[:session_data] || %{}
    }
  end

  defp to_naive_datetime(nil), do: nil
  defp to_naive_datetime(%NaiveDateTime{} = dt), do: dt
  defp to_naive_datetime(%DateTime{} = dt), do: DateTime.to_naive(dt)

  defp serialize_validation_results(nil), do: %{}

  defp serialize_validation_results(results) when is_map(results) do
    results
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Map.new()
  end
end
