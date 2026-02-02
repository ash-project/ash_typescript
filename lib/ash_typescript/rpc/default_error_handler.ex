# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.DefaultErrorHandler do
  @moduledoc """
  Default error handler for RPC operations.

  This handler returns errors as-is without any transformation.
  Variable interpolation is left to the client for better flexibility.

  This module is called as the last step in the error processing pipeline.
  """

  @doc """
  Default error handler that returns errors as-is.

  Previously this handler would interpolate variables into messages,
  but now we let the client handle that for better flexibility.

  The error is returned with the message template and vars separate,
  allowing the client to handle interpolation as needed.

  ## Examples

      iex> error = %{
      ...>   message: "Field %{field} is required",
      ...>   short_message: "Required field",
      ...>   vars: %{field: "email"},
      ...>   code: "required",
      ...>   fields: ["email"]
      ...> }
      iex> handle_error(error, %{})
      %{
        message: "Field %{field} is required",
        short_message: "Required field",
        vars: %{field: "email"},
        code: "required",
        fields: ["email"]
      }
  """
  @spec handle_error(map(), map()) :: map()
  def handle_error(error, _context) when is_map(error) do
    # Return error as-is, let client handle variable interpolation
    error
  end

  def handle_error(nil, _context), do: nil
end
