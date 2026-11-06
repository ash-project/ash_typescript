# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.CustomTypes.AliasCallbackErrorsTest do
  @moduledoc """
  A `typescript_type_alias/0` that doesn't return a string fails manifest
  compilation (`CustomTypes.check_alias_names/2`); the functions that read the
  alias afterwards raise with the same sentence when called on such a type.
  """
  use ExUnit.Case, async: true

  alias Ash.Info.Manifest.Type
  alias AshTypescript.Codegen.ScalarAliases
  alias AshTypescript.CustomTypes

  defmodule BadAlias do
    @moduledoc false
    use AshTypescript.Test.PassThroughType, storage: :string

    def typescript_type, do: "string"
    def typescript_type_alias, do: :not_a_string
  end

  @message "The typescript_type_alias/0 of #{inspect(BadAlias)} must return a string, got: :not_a_string."

  test "CustomTypes.names/2" do
    assert_raise ArgumentError, @message, fn ->
      CustomTypes.names(BadAlias, CustomTypes.builtin_only())
    end
  end

  test "ScalarAliases.name/2" do
    assert_raise ArgumentError, @message, fn ->
      ScalarAliases.name(%Type{kind: :unknown, module: BadAlias}, CustomTypes.builtin_only())
    end
  end
end
