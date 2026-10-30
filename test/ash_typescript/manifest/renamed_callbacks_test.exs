# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.RenamedCallbacksTest do
  # A type module the manifest reaches that still exports a callback under
  # its former name (`typescript_type_name/0`,
  # `typescript_alias_name/0`) fails compilation, naming the new callback
  # (`CustomTypes.check_renamed_callbacks/1`). Manifests are compiled with
  # `Module.create/3` under fixed names.
  use ExUnit.Case, async: false

  alias AshTypescript.Manifest.RenamedCallbacksTest, as: T

  defmodule OldScalar do
    @moduledoc false
    use AshTypescript.Test.PassThroughType, storage: :string

    def typescript_type_name, do: "string"
  end

  defmodule OldNewType do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: :string, constraints: [max_length: 10]

    def typescript_type_name, do: "string"
  end

  defmodule OldStruct do
    @moduledoc false
    use Ash.TypedStruct

    def typescript_alias_name, do: "OldStruct"

    typed_struct do
      field :a, :string
    end
  end

  defmodule OldDeclared do
    @moduledoc false
    use AshTypescript.Test.PassThroughType

    def typescript_fields, do: [lat: [type: :float, allow_nil?: false]]
    def typescript_alias_name, do: "OldDeclared"
  end

  defmodule OldBoth do
    @moduledoc false
    use AshTypescript.Test.PassThroughType, storage: :string

    def typescript_type_name, do: "string"
    def typescript_alias_name, do: "OldBoth"
  end

  defmodule OldRouteScalar do
    @moduledoc false
    use AshTypescript.Test.PassThroughType, storage: :string

    def typescript_type_name, do: "string"
  end

  defmodule Unreached do
    @moduledoc false
    use AshTypescript.Test.PassThroughType, storage: :string

    def typescript_type_name, do: "string"
  end

  defmodule OldMap do
    @moduledoc false
    use AshTypescript.Test.PassThroughType

    def typescript_type_name, do: "OldMap"
  end

  # An RPC resource with an attribute typed by `OldScalar`.
  defmodule AttrHolder do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "RenamedCallbacksAttrHolder"
    end

    attributes do
      uuid_primary_key :id
      attribute :old, T.OldScalar, public?: true
    end

    actions do
      defaults [:read]
    end
  end

  defmodule AttrHolderDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource T.AttrHolder do
        rpc_action :list_attr_holders, :read
      end
    end

    resources do
      resource T.AttrHolder
    end
  end

  # One generic action per type; each domain below exposes one of them.
  defmodule Holder do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "RenamedCallbacksHolder"
    end

    attributes do
      uuid_primary_key :id
    end

    actions do
      action :new_type, T.OldNewType do
        run fn _input, _context -> {:ok, "a"} end
      end

      action :struct, T.OldStruct do
        run fn _input, _context -> {:ok, nil} end
      end

      action :declared, T.OldDeclared do
        run fn _input, _context -> {:ok, %{}} end
      end

      action :both, T.OldBoth do
        run fn _input, _context -> {:ok, "a"} end
      end

      action :map, T.OldMap do
        run fn _input, _context -> {:ok, %{}} end
      end
    end
  end

  defmodule NewTypeDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource T.Holder do
        rpc_action :old_new_type, :new_type
      end
    end

    resources do
      resource T.Holder
    end
  end

  defmodule StructDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource T.Holder do
        rpc_action :old_struct, :struct
      end
    end

    resources do
      resource T.Holder
    end
  end

  defmodule DeclaredDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource T.Holder do
        rpc_action :old_declared, :declared
      end
    end

    resources do
      resource T.Holder
    end
  end

  defmodule BothDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource T.Holder do
        rpc_action :old_both, :both
      end
    end

    resources do
      resource T.Holder
    end
  end

  defmodule MapDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource T.Holder do
        rpc_action :old_map, :map
      end
    end

    resources do
      resource T.Holder
    end
  end

  # A typed controller whose route argument is the only use of `OldRouteScalar`.
  defmodule OldRouteSession do
    @moduledoc false
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.Manifest.RenamedCallbacksTest.OldRouteController

      get :lookup do
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
        argument :code, T.OldRouteScalar
      end
    end
  end

  # The scoped manifest prints the RPC resource warnings; they're captured.
  defp compile_manifest!(name, opts, body \\ nil) do
    module = Module.concat(T, name)

    ExUnit.CaptureIO.with_io(:stderr, fn ->
      Module.create(
        module,
        quote do
          use AshTypescript.Manifest, unquote([otp_app: :ash_typescript] ++ opts)
          unquote(body)
        end,
        Macro.Env.location(__ENV__)
      )
    end)

    module
  end

  defp compile_error!(name, opts) do
    error = assert_raise Spark.Error.DslError, fn -> compile_manifest!(name, opts) end
    message = Exception.message(error)
    assert message =~ "custom_types"
    message
  end

  defp type_message(module),
    do:
      "#{inspect(module)} exports `typescript_type_name/0`, which is now `typescript_type/0`: rename it."

  defp alias_message(module) do
    "#{inspect(module)} exports `typescript_alias_name/0`, which is now " <>
      "`typescript_type_alias/0`: rename it."
  end

  test "a scalar custom type exporting typescript_type_name/0 fails, naming typescript_type/0" do
    message = compile_error!(AttrManifest, domains: [T.AttrHolderDomain])

    assert message =~ type_message(T.OldScalar)
  end

  test "a NewType over :string exporting typescript_type_name/0" do
    message = compile_error!(NewTypeManifest, domains: [T.NewTypeDomain])

    assert message =~ type_message(T.OldNewType)
  end

  test "a TypedStruct exporting typescript_alias_name/0" do
    message = compile_error!(StructManifest, domains: [T.StructDomain])

    assert message =~ alias_message(T.OldStruct)
  end

  test "a declared map-like custom type exporting typescript_alias_name/0" do
    message = compile_error!(DeclaredManifest, domains: [T.DeclaredDomain])

    assert message =~ alias_message(T.OldDeclared)
  end

  test "a module exporting both gets both messages" do
    message = compile_error!(BothManifest, domains: [T.BothDomain])

    assert message =~ type_message(T.OldBoth) <> " " <> alias_message(T.OldBoth)
  end

  test "a type reached only by a typed controller route argument" do
    message =
      compile_error!(RouteManifest,
        domains: [AshTypescript.Test.SecondDomain],
        typed_controllers: [T.OldRouteSession]
      )

    assert message =~ type_message(T.OldRouteScalar)
  end

  test "a module exporting an old callback that the manifest doesn't reach compiles" do
    module =
      compile_manifest!(
        UnreachedManifest,
        [domains: [AshTypescript.Test.SecondDomain]],
        quote do
          custom_types do
            scalar AshTypescript.Manifest.RenamedCallbacksTest.Unreached, :string
          end
        end
      )

    assert Code.ensure_loaded?(module)
  end

  test "a map-like :unknown type with the old callback and no fields fails in ash_rpc's decoration first" do
    # Spark wraps the decorator's AshRpc.Manifest.UntypedStructError.
    error =
      assert_raise RuntimeError, fn -> compile_manifest!(MapManifest, domains: [T.MapDomain]) end

    message = Exception.message(error)

    assert message =~
             ~s[Entrypoint "old_map" (#{inspect(T.Holder)}, action :map) returns ] <>
               "an undeclared custom type, #{inspect(T.OldMap)}, at returns."

    refute message =~ "which is now `typescript_type/0`"
  end
end
