# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.SpecHelpers do
  @moduledoc """
  Test helpers for working with `%Ash.Info.Manifest.Action{}` values.

  Schema generation entry points (`ZodSchemaGenerator.generate_zod_schema/3`,
  `ValibotSchemaGenerator.generate_valibot_schema/3`) consume spec-shaped
  inputs. Tests that previously passed raw `Ash.Resource.Info.action/2` results
  should use `spec_action/2` instead.
  """

  @doc """
  Returns the decorated `%Ash.Info.Manifest.Action{}` for `resource`'s
  `action_name` entrypoint action, from `AshTypescript.action_lookup/0` (so
  `AshTypescript.with_manifest/2` applies).

  Codegen reads input, field and member names from the action's decoration, so
  an action outside the manifest raises: build an
  `AshTypescript.Test.InlineManifest` that contains it and wrap the call in
  `AshTypescript.with_manifest/2`.
  """
  @spec spec_action(module(), atom()) :: Ash.Info.Manifest.Action.t()
  def spec_action(resource, action_name) do
    case Map.get(AshTypescript.action_lookup(), {resource, action_name}) do
      %Ash.Info.Manifest.Action{} = action ->
        action

      nil ->
        raise ArgumentError,
              "#{inspect(resource)}.#{action_name} is not an entrypoint action in the manifest"
    end
  end
end
