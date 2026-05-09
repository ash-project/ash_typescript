# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.SpecHelpers do
  @moduledoc """
  Test helpers for working with `%AshApiSpec.Action{}` values.

  Schema generation entry points (`ZodSchemaGenerator.generate_zod_schema/3`,
  `ValibotSchemaGenerator.generate_valibot_schema/3`) consume spec-shaped
  inputs. Tests that previously passed raw `Ash.Resource.Info.action/2` results
  should use `spec_action/2` instead.
  """

  @doc """
  Builds an `%AshApiSpec.Action{}` for `resource`'s `action_name` action.
  """
  @spec spec_action(module(), atom()) :: AshApiSpec.Action.t()
  def spec_action(resource, action_name) do
    raw = Ash.Resource.Info.action(resource, action_name)
    AshApiSpec.Generator.ActionBuilder.build(resource, raw, [])
  end
end
