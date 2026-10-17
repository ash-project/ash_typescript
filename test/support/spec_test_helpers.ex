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
  Builds an `%Ash.Info.Manifest.Action{}` for `resource`'s `action_name` action.

  Its input and return types are decorated as the manifest decorates them, so
  codegen names their typed-container fields from the decoration.
  """
  @spec spec_action(module(), atom()) :: Ash.Info.Manifest.Action.t()
  def spec_action(resource, action_name) do
    raw = Ash.Resource.Info.action(resource, action_name)
    action = Ash.Info.Manifest.Generator.ActionBuilder.build(resource, raw, [])

    %{
      action
      | inputs: Enum.map(action.inputs, &%{&1 | type: decorate(&1.type)}),
        returns: action.returns && decorate(action.returns)
    }
  end

  defp decorate(type) do
    AshRpc.Manifest.Decorator.decorate_type(
      type,
      AshTypescript.output_field_formatter(),
      AshTypescript.RpcMappingSource
    )
  end
end
