# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ErrorHandler do
  @moduledoc """
  Behaviour for custom RPC error handlers.

  Error handlers allow you to customize how errors are transformed
  and presented to TypeScript clients. They are called after the
  Error protocol transformation but before the final response.

  ## Context

  The context map passed to handle_error/2 may contain:
  - `:domain` - The domain module
  - `:resource` - The resource module
  - `:action` - The action being performed
  - `:actor` - The actor performing the action
  - Additional application-specific context

  ## Example Implementation

      defmodule MyApp.CustomErrorHandler do
        @behaviour AshTypescript.Rpc.ErrorHandler

        def handle_error(error, context) do
          # Add custom error tracking
          Logger.error("RPC Error: \#{inspect(error)}")

          # Customize error format
          error
          |> Map.put(:timestamp, DateTime.utc_now())
          |> Map.update(:message, "Error", &translate_message/1)
        end

        defp translate_message(message) do
          # Custom translation logic
          message
        end
      end
  """

  @doc """
  Handles an error by transforming it before sending to the client.

  Receives an error map that has already been processed by the Error protocol,
  and a context map with additional information.

  Should return a modified error map or nil to filter out the error.
  """
  @callback handle_error(error :: map(), context :: map()) :: map() | nil
end
