# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.InputNameCollisionsTest do
  @moduledoc """
  Two inputs of one action with the same client name fail manifest compile
  with ash_rpc's `NameCollisionError`, raised while the manifest is decorated.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Test.InlineManifest

  defmodule MergedArgs do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "InputCollisionMergedArgs"
    end

    attributes do
      uuid_primary_key :id
    end

    actions do
      defaults [:read]

      action :merge, :boolean do
        argument :foo_bar, :string
        argument :foo__bar, :string
        run fn _input, _ctx -> {:ok, true} end
      end
    end
  end

  defmodule MergedArgsDomain do
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource MergedArgs do
        rpc_action :input_collision_merge, :merge
      end
    end

    resources do
      resource MergedArgs
    end
  end

  defmodule ArgVsAttribute do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "InputCollisionArgVsAttribute"
      argument_names create_titled: [title_: "title"]
    end

    attributes do
      uuid_primary_key :id
      attribute :title, :string, public?: true
    end

    actions do
      defaults [:read]

      create :create_titled do
        accept [:title]
        argument :title_, :string
      end
    end
  end

  defmodule ArgVsAttributeDomain do
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource ArgVsAttribute do
        rpc_action :input_collision_create_titled, :create_titled
      end
    end

    resources do
      resource ArgVsAttribute
    end
  end

  defmodule MappedArg do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "InputCollisionMappedArg"
      argument_names lookup: [external_id: "userId"]
    end

    attributes do
      uuid_primary_key :id
    end

    actions do
      defaults [:read]

      action :lookup, :boolean do
        argument :user_id, :string
        argument :external_id, :string
        run fn _input, _ctx -> {:ok, true} end
      end
    end
  end

  defmodule MappedArgDomain do
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource MappedArg do
        rpc_action :input_collision_lookup, :lookup
      end
    end

    resources do
      resource MappedArg
    end
  end

  defp build_error(domain) do
    assert_raise RuntimeError, fn -> InlineManifest.build!(domains: [domain]) end
  end

  test "two inputs mapping to one client name" do
    assert build_error(MergedArgsDomain).message =~
             "Client name collision in action :merge on #{inspect(MergedArgs)}: " <>
               ~s(:foo_bar and :foo__bar both map to "fooBar")
  end

  test "an argument and an accepted attribute with one client name" do
    assert build_error(ArgVsAttributeDomain).message =~
             "Client name collision in action :create_titled on #{inspect(ArgVsAttribute)}: " <>
               ~s(:title and :title_ both map to "title")
  end

  test "an argument_names mapping colliding with another input" do
    assert build_error(MappedArgDomain).message =~
             "Client name collision in action :lookup on #{inspect(MappedArg)}: " <>
               ~s(:user_id and :external_id both map to "userId")
  end
end
