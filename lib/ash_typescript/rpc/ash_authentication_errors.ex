# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# ash_rpc depends only on ash, so it cannot ship impls for optional
# AshAuthentication errors. ash_typescript keeps them (it already depends
# on ash_authentication optionally).
if Code.ensure_loaded?(AshAuthentication.Errors.AuthenticationFailed) do
  defimpl AshRpc.Error, for: AshAuthentication.Errors.AuthenticationFailed do
    def to_error(error) do
      %{
        message: Exception.message(error),
        short_message: "Authentication failed",
        vars: Map.new(error.vars || []),
        type: "authentication_failed",
        fields: List.wrap(error.field),
        path: error.path || []
      }
    end
  end
end

if Code.ensure_loaded?(AshAuthentication.Errors.InvalidToken) do
  defimpl AshRpc.Error, for: AshAuthentication.Errors.InvalidToken do
    def to_error(error) do
      %{
        message: Exception.message(error),
        short_message: "Invalid token",
        vars: Map.new(error.vars || []),
        type: "invalid_token",
        fields: List.wrap(error.field),
        path: error.path || []
      }
    end
  end
end
