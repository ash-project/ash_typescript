# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.CustomTypeErrorsTest do
  # `VerifyMappableTypes` reports, in one aggregated error, map-like custom
  # types that no RPC action reaches and that declare no fields, and map-like
  # or declared custom types that declare a TypeScript type
  # (`typescript_type_name/0` or a `scalar` entry). Map-like uses on the wire
  # are rejected earlier, by ash_rpc's decorator.
  use ExUnit.Case, async: false

  alias AshTypescript.CustomTypes.Scalar
  alias AshTypescript.Manifest.CustomTypeErrorsTest, as: T
  alias AshTypescript.Manifest.Verifiers.VerifyMappableTypes

  defmodule MapStorage do
    @moduledoc false
    defmacro __using__(_) do
      quote do
        use Ash.Type

        @impl true
        def storage_type(_), do: :map
        @impl true
        def cast_input(value, _), do: {:ok, value}
        @impl true
        def cast_stored(value, _), do: {:ok, value}
        @impl true
        def dump_to_native(value, _), do: {:ok, value}
      end
    end
  end

  defmodule UndeclaredBlob do
    @moduledoc false
    use MapStorage
  end

  defmodule NamedBlob do
    @moduledoc false
    use MapStorage

    def typescript_type_name, do: "NamedBlob"
  end

  defmodule ScalarBlob do
    @moduledoc false
    use MapStorage
  end

  defmodule NamedComposite do
    @moduledoc false
    # Declared by `composite_types/1`, and still naming a TypeScript type.
    use MapStorage

    def typescript_type_name, do: "NamedComposite"

    @impl true
    def composite?(_), do: true
    @impl true
    def composite_types(_), do: [{:label, :string, []}]
  end

  # The attributes are off the wire: the only RPC action is generic, so the
  # resource's records aren't reachable from it.
  defmodule Holder do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "CustomTypeErrorsHolder"
    end

    attributes do
      uuid_primary_key :id
      attribute :undeclared_blob, T.UndeclaredBlob, public?: true
      attribute :named_blob, T.NamedBlob, public?: true
      attribute :scalar_blob, T.ScalarBlob, public?: true
    end

    actions do
      action :get_named, T.NamedComposite do
        run fn _input, _context -> {:ok, %{label: "a"}} end
      end
    end
  end

  defmodule HolderDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource T.Holder do
        rpc_action :get_named, :get_named
      end
    end

    resources do
      resource T.Holder
    end
  end

  defp compile_manifest!(name, body) do
    module = Module.concat(T, name)

    unless Code.ensure_loaded?(module) do
      ExUnit.CaptureIO.with_io(:stderr, fn ->
        Module.create(
          module,
          quote do
            use AshTypescript.Manifest,
              otp_app: :ash_typescript,
              domains: [AshTypescript.Manifest.CustomTypeErrorsTest.HolderDomain]

            unquote(body)
          end,
          Macro.Env.location(__ENV__)
        )
      end)
    end

    module
  end

  defp scalar_manifest! do
    compile_manifest!(
      ScalarManifest,
      quote do
        custom_types do
          scalar AshTypescript.Manifest.CustomTypeErrorsTest.ScalarBlob, :string
        end
      end
    )
  end

  defp section(message, heading) do
    [_, rest] = String.split(message, heading, parts: 2)
    rest |> String.split(~r/\n(?=\S)/) |> hd()
  end

  describe "one aggregated error" do
    setup do
      assert {:error, message} = AshTypescript.Manifest.run_verifiers(scalar_manifest!())
      %{message: message}
    end

    test "lists an off-wire map-like custom type without fields, with the hint", %{
      message: message
    } do
      undeclared = section(message, "Undeclared map-like custom types found")

      assert undeclared =~
               "  • #{inspect(T.UndeclaredBlob)}\n" <>
                 "      - resource #{inspect(T.Holder)}, field :undeclared_blob"

      refute undeclared =~ inspect(T.NamedBlob)
      refute undeclared =~ inspect(T.ScalarBlob)

      assert message =~
               "Declare its fields with a `map` entry in your manifest module's " <>
                 "`custom_types` section, a `typescript_fields/0` callback on the type, or " <>
                 "`composite?/1` + `composite_types/1`."
    end

    test "lists map-like and declared custom types that declare a TypeScript type", %{
      message: message
    } do
      declaring = section(message, "Map-like custom types that declare a TypeScript type")

      assert declaring =~
               "  • #{inspect(T.NamedBlob)}\n" <>
                 "      - resource #{inspect(T.Holder)}, field :named_blob"

      assert declaring =~
               "  • #{inspect(T.NamedComposite)}\n" <>
                 "      - type NamedComposite (#{inspect(T.NamedComposite)})"

      assert declaring =~
               "  • #{inspect(T.ScalarBlob)}\n" <>
                 "      - resource #{inspect(T.Holder)}, field :scalar_blob"

      refute declaring =~ inspect(T.UndeclaredBlob)

      assert declaring =~
               "`#{inspect(T.NamedComposite)}` is map-like (`storage_type :map` / composite) " <>
                 "or declares fields, so its TypeScript type is generated from its fields and " <>
                 "can't be declared. Remove `typescript_type_name/0`, or turn the `scalar` " <>
                 "declaration into a `map` one."

      assert declaring =~
               "For more precise member types, use scalar custom types with their own TS " <>
                 "mapping as field types (for example a NewType over `:string` with " <>
                 "`typescript_type_name/0`)."
    end

    test "doesn't list them as unsupported types", %{message: message} do
      refute message =~ "Unsupported types found"
    end
  end

  test "a built-in scalar entry for a map-like type is reported" do
    module = scalar_manifest!()
    manifest = AshTypescript.manifest(module)
    custom_types = manifest.custom.ash_typescript.custom_types
    {%Scalar{} = entry, declared} = Map.pop(custom_types.declared, T.ScalarBlob)

    custom_types = %{
      custom_types
      | declared: declared,
        builtin: Map.put(custom_types.builtin, T.ScalarBlob, entry)
    }

    manifest = put_in(manifest.custom.ash_typescript.custom_types, custom_types)

    assert {:error, error} =
             VerifyMappableTypes.verify(%{persist: %{manifest: manifest, module: module}})

    declaring =
      error
      |> Exception.message()
      |> section("Map-like custom types that declare a TypeScript type")

    assert declaring =~
             "  • #{inspect(T.ScalarBlob)}\n" <>
               "      - resource #{inspect(T.Holder)}, field :scalar_blob"
  end

  test "map entries for the off-wire types pass, as does a composite without a TS name" do
    module =
      compile_manifest!(
        MapManifest,
        quote do
          custom_types do
            map AshTypescript.Manifest.CustomTypeErrorsTest.UndeclaredBlob do
              field :a, :string
            end

            map AshTypescript.Manifest.CustomTypeErrorsTest.ScalarBlob do
              field :a, :string
            end
          end
        end
      )

    assert {:error, message} = AshTypescript.Manifest.run_verifiers(module)

    # Only the two types exporting `typescript_type_name/0` remain.
    declaring = section(message, "Map-like custom types that declare a TypeScript type")
    assert declaring =~ inspect(T.NamedBlob)
    assert declaring =~ inspect(T.NamedComposite)
    refute message =~ inspect(T.UndeclaredBlob)
    refute message =~ inspect(T.ScalarBlob)
  end
end
