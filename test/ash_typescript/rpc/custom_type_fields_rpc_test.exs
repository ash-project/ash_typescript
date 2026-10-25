# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.CustomTypeFieldsRpcTest do
  # Custom types with declared fields over RPC: they are typed maps, so the
  # client selects their fields, input keys are client names, and output has
  # only the declared fields, under client names.
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc.CustomTypeFieldsRpcTest, as: T
  alias AshTypescript.Test.TestHelpers

  defmodule Swatch do
    @moduledoc false
    # Declared only by a manifest `map` entry, with a multi-word field.
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

  defmodule Canvas do
    @moduledoc false
    use Ash.Resource,
      domain: AshTypescript.Rpc.CustomTypeFieldsRpcTest.CanvasDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "FieldsCanvas"
    end

    attributes do
      uuid_primary_key :id, public?: true
      attribute :swatch, AshTypescript.Rpc.CustomTypeFieldsRpcTest.Swatch, public?: true
    end

    actions do
      defaults [:read, create: [:swatch]]
    end
  end

  defmodule CanvasDomain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Rpc.CustomTypeFieldsRpcTest.Canvas do
        rpc_action :create_fields_canvas, :create
      end
    end

    resources do
      resource AshTypescript.Rpc.CustomTypeFieldsRpcTest.Canvas
    end
  end

  defp canvas_manifest do
    module = Module.concat(T, CanvasManifest)

    unless Code.ensure_loaded?(module) do
      ExUnit.CaptureIO.with_io(:stderr, fn ->
        Module.create(
          module,
          quote do
            use AshTypescript.Manifest,
              otp_app: :ash_typescript,
              domains: [AshTypescript.Rpc.CustomTypeFieldsRpcTest.CanvasDomain]

            custom_types do
              map AshTypescript.Rpc.CustomTypeFieldsRpcTest.Swatch do
                field :hex_code, :string, allow_nil?: false
                field :display_name, :string, client_name: "label"
              end
            end
          end,
          Macro.Env.location(__ENV__)
        )
      end)
    end

    AshTypescript.manifest(module)
  end

  defp run(params),
    do: AshRpc.run_action(AshTypescript.RpcProfile, TestHelpers.build_rpc_conn(), params)

  describe "the built-in Money entry (Task.price)" do
    test "input and output use its fields" do
      result =
        run(%{
          "action" => "create_task",
          "input" => %{
            "title" => "Priced",
            "price" => %{"currency" => "USD", "amount" => "10.50"}
          },
          "fields" => ["id", %{"price" => ["currency", "amount"]}]
        })

      assert %{"success" => true, "data" => %{"price" => price}} = result
      assert price == %{"currency" => "USD", "amount" => "10.50"}
    end

    test "a stored key Money doesn't declare isn't returned" do
      task =
        AshTypescript.Test.Task
        |> Ash.Changeset.for_create(:create, %{
          title: "Formatted",
          price: %{currency: "EUR", amount: "3", format_options: [fractional_digits: 2]}
        })
        |> Ash.create!(authorize?: false)

      assert task.price.format_options == [fractional_digits: 2]

      result =
        run(%{
          "action" => "list_tasks",
          "filter" => %{"id" => %{"eq" => task.id}},
          "fields" => ["id", %{"price" => ["currency", "amount"]}]
        })

      assert %{"success" => true, "data" => [%{"price" => price}]} = result
      assert price == %{"currency" => "EUR", "amount" => "3"}
    end

    test "selecting it bare is a requires_field_selection error" do
      result = run(%{"action" => "list_tasks", "fields" => ["id", "price"]})

      assert %{"success" => false, "errors" => [error]} = result
      assert error["type"] == "requires_field_selection"
      assert error["fields"] == ["price"]
    end
  end

  describe "a manifest map entry with a multi-word field and a client_name" do
    test "input and output use the formatter's and the entry's client names" do
      AshTypescript.with_manifest(canvas_manifest(), fn ->
        result =
          run(%{
            "action" => "create_fields_canvas",
            "input" => %{"swatch" => %{"hexCode" => "#ffffff", "label" => "White"}},
            "fields" => ["id", %{"swatch" => ["hexCode", "label"]}]
          })

        assert %{"success" => true, "data" => %{"swatch" => swatch}} = result
        assert swatch == %{"hexCode" => "#ffffff", "label" => "White"}
      end)
    end

    test "an input key that isn't a client name is unknown_input" do
      AshTypescript.with_manifest(canvas_manifest(), fn ->
        result =
          run(%{
            "action" => "create_fields_canvas",
            "input" => %{"swatch" => %{"hex_code" => "#ffffff"}},
            "fields" => ["id"]
          })

        assert %{"success" => false, "errors" => [error]} = result
        assert error["type"] == "unknown_input"
        assert error["fields"] == ["hex_code"]
        assert error["path"] == ["swatch"]
      end)
    end
  end
end
