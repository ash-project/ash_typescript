# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defprotocol AshTypescript.Rpc.Error do
  @moduledoc """
  Protocol for extracting minimal information from exceptions for RPC responses.

  Similar to AshGraphql.Error, this protocol transforms various error types into
  a standardized format with only the essential information needed by TypeScript clients.

  ## Error Format

  Each implementation should return a map with these fields:
  - `:message` - The full error message (may contain template variables like %{key})
  - `:short_message` - A concise version of the message
  - `:type` - A machine-readable error type (e.g., "invalid_changes", "not_found")
  - `:vars` - A map of variables to interpolate into messages
  - `:fields` - A list of affected field names (for field-level errors)
  - `:path` - The path to the error location in the data structure
  - `:details` - An optional map with extra details

  ## Example Implementation

      defimpl AshTypescript.Rpc.Error, for: MyApp.CustomError do
        def to_error(error) do
          %{
            message: error.message,
            short_message: "Custom error occurred",
            type: "custom_error",
            vars: %{detail: error.detail},
            fields: [],
            path: error.path || []
          }
        end
      end
  """

  @doc """
  Transforms an exception into a minimal error representation for RPC responses.
  """
  @spec to_error(Exception.t()) :: map()
  def to_error(exception)
end

defimpl AshTypescript.Rpc.Error, for: Ash.Error.Changes.InvalidChanges do
  def to_error(error) do
    %{
      message: Map.get(error, :message) || Exception.message(error),
      short_message: "Invalid changes",
      vars: Map.new(error.vars || []),
      type: "invalid_changes",
      fields: List.wrap(error.fields),
      path: error.path || []
    }
  end
end

defimpl AshTypescript.Rpc.Error, for: Ash.Error.Query.InvalidQuery do
  def to_error(error) do
    %{
      message: Map.get(error, :message) || Exception.message(error),
      short_message: "Invalid query",
      vars: Map.new(error.vars || []),
      type: "invalid_query",
      fields: List.wrap(Map.get(error, :fields) || Map.get(error, :field)),
      path: error.path || []
    }
  end
end

defimpl AshTypescript.Rpc.Error, for: Ash.Error.Query.NotFound do
  def to_error(error) do
    %{
      message: Exception.message(error),
      short_message: "Not found",
      vars: Map.new(error.vars || []),
      type: "not_found",
      fields: [],
      path: error.path || []
    }
  end
end

defimpl AshTypescript.Rpc.Error, for: Ash.Error.Changes.Required do
  def to_error(error) do
    %{
      message: Exception.message(error),
      short_message: "Required field",
      vars: Map.new(error.vars || []) |> Map.put(:field, error.field),
      type: "required",
      fields: List.wrap(error.field),
      path: error.path || []
    }
  end
end

defimpl AshTypescript.Rpc.Error, for: Ash.Error.Query.Required do
  def to_error(error) do
    %{
      message: Exception.message(error),
      short_message: "Required field",
      vars: Map.new(error.vars || []) |> Map.put(:field, error.field),
      type: "required",
      fields: List.wrap(error.field),
      path: error.path || []
    }
  end
end

defimpl AshTypescript.Rpc.Error, for: Ash.Error.Forbidden.Policy do
  def to_error(error) do
    base = %{
      message: Exception.message(error),
      short_message: "Forbidden",
      vars: %{},
      type: "forbidden",
      fields: [],
      path: error.path || []
    }

    # Optionally include policy details if configured to do so
    if Map.get(error, :policy_breakdown?) do
      Map.put(base, :policy_breakdown, Map.get(error, :policies))
    else
      base
    end
  end
end

defimpl AshTypescript.Rpc.Error, for: Ash.Error.Forbidden.ForbiddenField do
  def to_error(error) do
    %{
      message: Exception.message(error),
      short_message: "Forbidden field",
      vars: Map.new(error.vars || []) |> Map.put(:field, error.field),
      type: "forbidden_field",
      fields: List.wrap(error.field),
      path: error.path || []
    }
  end
end

defimpl AshTypescript.Rpc.Error, for: Ash.Error.Changes.InvalidAttribute do
  def to_error(error) do
    %{
      message: Map.get(error, :message) || Exception.message(error),
      short_message: "Invalid attribute",
      vars: Map.new(error.vars || []) |> Map.put(:field, error.field),
      type: "invalid_attribute",
      fields: List.wrap(error.field),
      path: error.path || []
    }
  end
end

defimpl AshTypescript.Rpc.Error, for: Ash.Error.Changes.InvalidArgument do
  def to_error(error) do
    %{
      message: Map.get(error, :message) || Exception.message(error),
      short_message: "Invalid argument",
      vars: Map.new(error.vars || []) |> Map.put(:field, Map.get(error, :field)),
      type: "invalid_argument",
      fields: List.wrap(Map.get(error, :field)),
      path: error.path || []
    }
  end
end

defimpl AshTypescript.Rpc.Error, for: Ash.Error.Query.InvalidArgument do
  def to_error(error) do
    %{
      message: Map.get(error, :message) || Exception.message(error),
      short_message: "Invalid argument",
      vars: Map.new(error.vars || []) |> Map.put(:field, Map.get(error, :field)),
      type: "invalid_argument",
      fields: List.wrap(Map.get(error, :field)),
      path: error.path || []
    }
  end
end

defimpl AshTypescript.Rpc.Error, for: Ash.Error.Page.InvalidKeyset do
  def to_error(error) do
    %{
      message: Exception.message(error),
      short_message: "Invalid keyset",
      vars: Map.new(error.vars || []),
      type: "invalid_keyset",
      fields: [],
      path: error.path || []
    }
  end
end

defimpl AshTypescript.Rpc.Error, for: Ash.Error.Query.InvalidPage do
  def to_error(error) do
    %{
      message: Exception.message(error),
      short_message: "Invalid pagination",
      vars: Map.new(error.vars || []),
      type: "invalid_page",
      fields: [],
      path: error.path || []
    }
  end
end

defimpl AshTypescript.Rpc.Error, for: Ash.Error.Invalid.InvalidPrimaryKey do
  def to_error(error) do
    %{
      message: Exception.message(error),
      short_message: "Invalid primary key",
      vars: Map.new(error.vars || []),
      type: "invalid_primary_key",
      fields: [],
      path: error.path || []
    }
  end
end

defimpl AshTypescript.Rpc.Error, for: Ash.Error.Query.ReadActionRequiresActor do
  def to_error(error) do
    %{
      message: Exception.message(error),
      short_message: "Authentication required",
      vars: Map.new(error.vars || []),
      type: "forbidden",
      fields: [],
      path: error.path || []
    }
  end
end

defimpl AshTypescript.Rpc.Error, for: Ash.Error.Unknown.UnknownError do
  def to_error(error) do
    %{
      message: "Something went wrong",
      short_message: "Unknown error",
      vars: Map.new(error.vars || []),
      type: "unknown_error",
      fields: [],
      path: error.path || []
    }
  end
end

if Code.ensure_loaded?(AshAuthentication.Errors.AuthenticationFailed) do
  defimpl AshTypescript.Rpc.Error, for: AshAuthentication.Errors.AuthenticationFailed do
    def to_error(error) do
      %{
        message: Map.get(error, :message) || "Authentication failed",
        short_message: "Authentication failed",
        vars: Map.new(error.vars || []),
        type: "authentication_failed",
        fields: List.wrap(Map.get(error, :field)),
        path: error.path || []
      }
    end
  end
end

if Code.ensure_loaded?(AshAuthentication.Errors.InvalidToken) do
  defimpl AshTypescript.Rpc.Error, for: AshAuthentication.Errors.InvalidToken do
    def to_error(error) do
      %{
        message: Map.get(error, :message) || "Invalid token",
        short_message: "Invalid token",
        vars: Map.new(error.vars || []),
        type: "invalid_token",
        fields: [],
        path: error.path || []
      }
    end
  end
end
