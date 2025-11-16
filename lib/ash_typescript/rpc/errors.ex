# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Errors do
  @moduledoc """
  Central error processing module for RPC operations.

  Handles error transformation, unwrapping, and formatting for TypeScript clients.
  Uses the AshTypescript.Rpc.Error protocol to extract minimal information from exceptions.
  """

  require Logger

  alias AshTypescript.Rpc.DefaultErrorHandler
  alias AshTypescript.Rpc.Error, as: ErrorProtocol

  @doc """
  Transforms errors into standardized RPC error responses.

  Processes errors through the following pipeline:
  1. Convert to Ash error class using Ash.Error.to_error_class
  2. Unwrap nested error structures
  3. Transform via Error protocol
  4. Apply resource-level error handler (if configured)
  5. Apply domain-level error handler (if configured)
  6. Interpolate variables into messages
  """
  @spec to_errors(term(), atom() | nil, atom() | nil, atom() | nil, map()) :: list(map())
  def to_errors(errors, domain \\ nil, resource \\ nil, action \\ nil, context \\ %{})

  def to_errors(errors, domain, resource, action, context) do
    # First ensure we have an Ash error class
    ash_error = Ash.Error.to_error_class(errors)

    # Then process the errors
    ash_error
    |> unwrap_errors()
    |> Enum.map(&process_single_error(&1, domain, resource, action, context))
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Unwraps nested error structures from Ash error classes.
  """
  @spec unwrap_errors(term()) :: list(term())
  def unwrap_errors(%{errors: errors}) when is_list(errors) do
    # Recursively unwrap nested errors
    Enum.flat_map(errors, &unwrap_errors/1)
  end

  def unwrap_errors(%{errors: error}) when not is_list(error) do
    unwrap_errors([error])
  end

  def unwrap_errors(errors) when is_list(errors) do
    Enum.flat_map(errors, &unwrap_errors/1)
  end

  def unwrap_errors(error) do
    # Single error - return as list
    [error]
  end

  defp process_single_error(error, domain, resource, _action, context) do
    transformed_error =
      if ErrorProtocol.impl_for(error) do
        try do
          ErrorProtocol.to_error(error)
        rescue
          e ->
            Logger.warning("""
            Failed to transform error via protocol: #{inspect(e)}
            Original error: #{inspect(error)}
            """)

            fallback_error_response(error)
        end
      else
        # No protocol implementation - use fallback
        handle_unimplemented_error(error)
      end

    # Apply resource-level error handler if configured
    transformed_error =
      if resource && function_exported?(resource, :handle_rpc_error, 2) do
        apply_error_handler(
          {resource, :handle_rpc_error, []},
          transformed_error,
          context
        )
      else
        transformed_error
      end

    # Apply domain-level error handler if configured
    transformed_error =
      if domain do
        handler = get_domain_error_handler(domain)
        apply_error_handler(handler, transformed_error, context)
      else
        transformed_error
      end

    # Apply default error handler for variable interpolation
    DefaultErrorHandler.handle_error(transformed_error, context)
  end

  defp apply_error_handler({module, function, args}, error, context) do
    case apply(module, function, [error, context | args]) do
      nil -> nil
      handled -> handled
    end
  rescue
    e ->
      Logger.warning("""
      Error handler failed: #{inspect(e)}
      Handler: #{inspect({module, function, args})}
      Original error: #{inspect(error)}
      """)

      error
  end

  defp get_domain_error_handler(domain) do
    # Check if domain has RPC configuration with error handler
    with true <- function_exported?(domain, :spark_dsl_config, 0),
         {:ok, handler} <-
           Spark.Dsl.Extension.fetch_opt(domain, [:typescript_rpc], :error_handler) do
      case handler do
        {module, function, args} -> {module, function, args}
        module when is_atom(module) -> {module, :handle_error, []}
        _ -> {DefaultErrorHandler, :handle_error, []}
      end
    else
      _ ->
        {DefaultErrorHandler, :handle_error, []}
    end
  end

  defp handle_unimplemented_error(error) when is_exception(error) do
    uuid = Ash.UUID.generate()

    Logger.warning("""
    Unhandled error in RPC (no protocol implementation).
    Error ID: #{uuid}
    Error type: #{inspect(error.__struct__)}
    Message: #{Exception.message(error)}

    To handle this error type, implement the AshTypescript.Rpc.Error protocol:

    defimpl AshTypescript.Rpc.Error, for: #{inspect(error.__struct__)} do
      def to_error(error) do
        %{
          message: error.message,
          short_message: "Error description",
          code: "error_code",
          vars: %{},
          fields: [],
          path: error.path || []
        }
      end
    end
    """)

    %{
      message: "Something went wrong. Unique error id: #{uuid}",
      short_message: "Internal error",
      code: "internal_error",
      vars: %{},
      fields: [],
      path: Map.get(error, :path, []),
      error_id: uuid
    }
  end

  defp handle_unimplemented_error(error) do
    uuid = Ash.UUID.generate()

    Logger.warning("""
    Unhandled non-exception error in RPC.
    Error ID: #{uuid}
    Error: #{inspect(error)}
    """)

    %{
      message: "Something went wrong. Unique error id: #{uuid}",
      short_message: "Internal error",
      code: "internal_error",
      vars: %{},
      fields: [],
      path: [],
      error_id: uuid
    }
  end

  defp fallback_error_response(error) when is_exception(error) do
    %{
      message: Exception.message(error),
      short_message: "Error",
      code: "error",
      vars: %{},
      fields: [],
      path: Map.get(error, :path, [])
    }
  end

  defp fallback_error_response(error) do
    %{
      message: inspect(error),
      short_message: "Error",
      code: "error",
      vars: %{},
      fields: [],
      path: []
    }
  end
end
