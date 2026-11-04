# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.NameCheckTest do
  # The walk: which slots a decorated manifest yields. Walk tests assert slots,
  # not verdicts (those are rows in `AshTypescript.NameValidationTest`). A test
  # tagged `W-…` carries over the shape of the old cases it names. The
  # "end to end" tests compile manifests with bad client and binding names and
  # assert the report the compile fails with.
  use ExUnit.Case, async: false

  alias AshTypescript.Codegen.ClientNames
  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Manifest.NameCheck
  alias AshTypescript.Manifest.NameCheckTest, as: T
  alias AshTypescript.Test.InlineManifest

  # ── fixtures ─────────────────────────────────────────────────────

  defmodule Note do
    @moduledoc false
    use Ash.Resource, data_layer: :embedded, extensions: [AshTypescript.Resource]

    typescript do
      type_name "NameCheckNote"
    end

    attributes do
      attribute :body, :string, public?: true
    end
  end

  defmodule Flags do
    @moduledoc false
    # A field-bearing NewType with typescript_field_names/0, used as an
    # attribute, an action argument and a route return.
    use Ash.Type.NewType,
      subtype_of: :map,
      constraints: [fields: [is_on?: [type: :boolean], plain: [type: :string]]]

    def typescript_field_names, do: [is_on?: "isOn"]
  end

  defmodule Score do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: :float
  end

  defmodule Tagged do
    @moduledoc false
    defstruct [:hex_code, :label]

    def typescript_field_names, do: [hex_code: "hexCode"]
  end

  defmodule Swatch do
    @moduledoc false
    # Declared by the `map` entry in `@swatch_entry`.
    use AshTypescript.Test.PassThroughType
  end

  defmodule Child do
    @moduledoc false
    use Ash.Resource,
      domain: AshTypescript.Manifest.NameCheckTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "NameCheckChild"
    end

    attributes do
      uuid_primary_key :id
      attribute :parent_id, :uuid, public?: true
    end

    actions do
      defaults [:read]
    end
  end

  defmodule Res do
    @moduledoc false
    use Ash.Resource,
      domain: AshTypescript.Manifest.NameCheckTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "NameCheckRes"
      field_names line_1: "lineOne"
      argument_names act: [code_1: "codeOne"]
    end

    attributes do
      uuid_primary_key :id
      attribute :title, :string, public?: true
      attribute :line_1, :string, public?: true
      attribute :priority, :integer, public?: true
      attribute :note, Note, public?: true
      attribute :flags, Flags, public?: true
      attribute :score, Score, public?: true
      attribute :swatch, Swatch, public?: true

      attribute :status, :union,
        public?: true,
        constraints: [types: [text: [type: :string], num: [type: :integer]]]

      attribute :settings, :map,
        public?: true,
        constraints: [
          fields: [
            theme: [type: :string],
            nested: [type: :map, constraints: [fields: [depth: [type: :integer]]]],
            choice: [
              type: :union,
              constraints: [types: [short: [type: :string], long: [type: :integer]]]
            ]
          ]
        ]

      attribute :prefs, :keyword, public?: true, constraints: [fields: [lang: [type: :string]]]

      attribute :pair, :tuple,
        public?: true,
        constraints: [fields: [x: [type: :integer], y: [type: :integer]]]

      attribute :entries, {:array, :map},
        public?: true,
        constraints: [items: [fields: [label: [type: :string]]]]

      attribute :tagged, :struct,
        public?: true,
        constraints: [
          instance_of: Tagged,
          fields: [hex_code: [type: :string], label: [type: :string]]
        ]
    end

    relationships do
      has_many :children, AshTypescript.Manifest.NameCheckTest.Child do
        public? true
        destination_attribute :parent_id
      end
    end

    aggregates do
      count :child_count, :children, public?: true
    end

    calculations do
      calculate :shout, :string, expr(title) do
        public? true
        argument :volume, :integer
      end

      calculate :summary, :map, expr(%{total: 1}) do
        public? true
        constraints fields: [total: [type: :integer]]
      end
    end

    actions do
      defaults [:read]

      create :create do
        accept [:title, :priority]
        argument :memo, :string
        argument :extra, :map, constraints: [fields: [hint: [type: :string]]]
        # Shares a relationship's name: the runtime names it as an argument.
        argument :children, {:array, :map}
      end

      update :rename do
        accept [:priority]
        argument :title, :string
      end

      action :act, :string do
        argument :code_1, :string

        argument :choice, :union,
          constraints: [types: [left: [type: :string], right: [type: :integer]]]

        argument :flags, Flags
        run fn _input, _context -> {:ok, "x"} end
      end

      read :with_meta do
        metadata :rank, :integer
        metadata :total_2, :integer
      end
    end
  end

  defmodule Domain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Manifest.NameCheckTest.Res do
        rpc_action :list_res, :read
        rpc_action :create_res, :create
        rpc_action :rename_res, :rename
        rpc_action :act_res, :act
        rpc_action :act_res_again, :act

        rpc_action :meta_res, :with_meta,
          show_metadata: [:rank, :total_2],
          metadata_field_names: [total_2: "totalTwo"]
      end

      resource AshTypescript.Manifest.NameCheckTest.Child do
        rpc_action :list_children, :read

        typed_query :child_page, :read do
          fields [:id]
        end

        typed_query :child_named, :read do
          ts_fields_const_name "childNamedFields"
          ts_result_type_name "ChildNamedResult"
          fields [:id]
        end
      end
    end

    resources do
      resource AshTypescript.Manifest.NameCheckTest.Res
      resource AshTypescript.Manifest.NameCheckTest.Child
    end
  end

  defmodule Controller do
    @moduledoc false
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.Test.NameCheckController

      post :save do
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
        argument :mode, :string
        argument :opts, :map, constraints: [fields: [level: [type: :integer]]]
        returns {:array, :map}

        constraints items: [
                      fields: [
                        address: [type: :map, constraints: [fields: [line: [type: :string]]]],
                        first_name: [type: :string]
                      ]
                    ]
      end

      get :flags do
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
        returns AshTypescript.Manifest.NameCheckTest.Flags
      end

      post :login do
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
        argument :code, :string
        zod_schema_name "loginRouteZod"
        valibot_schema_name "loginRouteValibot"
      end
    end
  end

  @swatch_entry (quote do
                   map AshTypescript.Manifest.NameCheckTest.Swatch do
                     field :hex, :string, client_name: "hexCode"
                     field :alpha, :float
                   end
                 end)

  defp manifest do
    InlineManifest.build!(
      domains: [T.Domain],
      typed_controllers: [T.Controller],
      body: InlineManifest.app_custom_types([@swatch_entry])
    )
  end

  defp slots(manifest), do: NameCheck.slots(manifest, Custom.custom_types(manifest))

  # The probe's bad names, as raw name and client name pairs to rename in the
  # decorated manifest of the valid gap fixtures (`inject/2`).
  @client_gaps %{
    :emb_dash => :"emb-dash",
    "embDash" => "emb-dash",
    :attr_dash => :"attr-dash",
    "attrDash" => "attr-dash",
    :member_dash => :"member-dash",
    "memberDash" => "member-dash",
    :calc_arg_dash => :"calc-arg-dash",
    "calcArgDash" => "calc-arg-dash",
    :calc_arg_q => :calc_arg?,
    "calcArgQ" => "calcArg?",
    :arg_dash => :"arg-dash",
    "argDash" => "arg-dash",
    :m2_dash => :"m2-dash",
    "m2Dash" => "m2-dash",
    :m2_okq => :m2_ok?,
    "m2Okq" => "m2Ok?",
    :meta_dash => :"meta-dash",
    "metaDash" => "meta-dash"
  }

  # The probe's bad binding names: an rpc_action name, a typed query's
  # ts_fields_const_name and ts_result_type_name, a route's zod_schema_name.
  @binding_gaps %{
    :list_todos_gap => :"list-todos",
    "list_todos_gap" => "list-todos",
    "dashBoard" => "dash-board",
    "DashResult" => "Dash-Result",
    "loginSchema" => "login-schema"
  }

  # Replaces every term of `renames` (atoms and strings) throughout a
  # decorated manifest, map keys included: raw names, the client names of the
  # `custom.ash_rpc` decoration, entrypoints and `custom.ash_typescript`
  # config. Gives a walk or report test a name the wired checks would reject
  # when the manifest compiles.
  defp inject(term, renames) do
    case renames do
      %{^term => renamed} -> renamed
      _ -> inject_inside(term, renames)
    end
  end

  defp inject_inside(term, renames) when is_map(term),
    do:
      term |> Map.to_list() |> Map.new(fn {k, v} -> {inject(k, renames), inject(v, renames)} end)

  defp inject_inside(term, renames) when is_list(term), do: Enum.map(term, &inject(&1, renames))

  defp inject_inside(term, renames) when is_tuple(term),
    do: term |> Tuple.to_list() |> Enum.map(&inject(&1, renames)) |> List.to_tuple()

  defp inject_inside(term, _renames), do: term

  defp view(slot), do: Map.take(slot, [:kind, :owner, :path, :raw, :name, :source, :bare?])

  defp client_slots(manifest, filter) do
    manifest |> slots() |> Enum.filter(&(&1.family == :client and filter.(&1)))
  end

  defp views(manifest, filter), do: manifest |> client_slots(filter) |> Enum.map(&view/1)

  defp slot(kind, owner, raw, name, source, path \\ []),
    do: %{
      kind: kind,
      owner: owner,
      path: path,
      raw: raw,
      name: name,
      source: source,
      bare?: false
    }

  defp owned_by(owner), do: &(&1.owner == owner)
  defp raw_is(raw), do: &(&1.raw == raw)

  @res_rpc [:create_res]

  # ── client slots, per kind ───────────────────────────────────────

  describe "client slots, per kind" do
    test "an attribute is a resource_field slot" do
      assert views(manifest(), &(&1.raw == :title and &1.kind == :resource_field)) ==
               [slot(:resource_field, {:resource, T.Res}, :title, "title", :formatter)]
    end

    test "a calculation is a resource_field slot" do
      assert views(manifest(), raw_is(:shout)) ==
               [slot(:resource_field, {:resource, T.Res}, :shout, "shout", :formatter)]
    end

    test "an aggregate is a resource_field slot" do
      assert views(manifest(), raw_is(:child_count)) ==
               [slot(:resource_field, {:resource, T.Res}, :child_count, "childCount", :formatter)]
    end

    test "a relationship is a resource_field slot" do
      assert views(manifest(), &(&1.raw == :children and &1.kind == :resource_field)) ==
               [slot(:resource_field, {:resource, T.Res}, :children, "children", :formatter)]
    end

    test "an embedded resource's field is a resource_field slot under the embedded resource" do
      assert views(manifest(), raw_is(:body)) ==
               [slot(:resource_field, {:resource, T.Note}, :body, "body", :formatter)]
    end

    test "a resource field slot says whether its resource has the AshTypescript.Resource extension" do
      slots = AshTypescript.manifest() |> slots() |> Enum.filter(&(&1.kind == :resource_field))

      exposed_of = fn r ->
        slots |> Enum.filter(owned_by({:resource, r})) |> Enum.map(& &1.exposed?) |> Enum.uniq()
      end

      assert exposed_of.(AshTypescript.Test.TodoContent.TextContent) == [false]
      assert exposed_of.(AshTypescript.Test.Todo) == [true]
    end

    test "a calculation argument is a calculation_argument slot" do
      assert views(manifest(), raw_is(:volume)) ==
               [
                 slot(
                   :calculation_argument,
                   {:calculation, :shout, T.Res},
                   :volume,
                   "volume",
                   :formatter
                 )
               ]
    end

    test "an action argument is an action_argument slot" do
      assert views(manifest(), raw_is(:memo)) ==
               [
                 slot(
                   :action_argument,
                   {:action, :create, T.Res, @res_rpc},
                   :memo,
                   "memo",
                   :formatter
                 )
               ]
    end

    test "an argument_names value has source {:argument_names, Resource, action}" do
      assert views(manifest(), raw_is(:code_1)) ==
               [
                 slot(
                   :action_argument,
                   {:action, :act, T.Res, [:act_res, :act_res_again]},
                   :code_1,
                   "codeOne",
                   {:argument_names, T.Res, :act}
                 )
               ]
    end

    test "an argument sharing a field's name is the field's slot only" do
      assert views(manifest(), raw_is(:title)) ==
               [slot(:resource_field, {:resource, T.Res}, :title, "title", :formatter)]
    end

    test "an argument sharing a relationship's name is an action_argument slot" do
      assert [
               %{kind: :action_argument, owner: {:action, :create, T.Res, _}, name: "children"}
             ] = client_slots(manifest(), &(&1.raw == :children and &1.kind == :action_argument))
    end

    test "an accepted attribute has no action_argument slot" do
      assert views(manifest(), raw_is(:priority)) ==
               [slot(:resource_field, {:resource, T.Res}, :priority, "priority", :formatter)]
    end

    test "metadata is a metadata_field slot under the RPC action" do
      assert views(manifest(), &(&1.kind == :metadata_field)) |> Enum.sort_by(& &1.raw) ==
               [
                 slot(
                   :metadata_field,
                   {:rpc_action, :meta_res, T.Res},
                   :rank,
                   "rank",
                   :formatter
                 ),
                 slot(
                   :metadata_field,
                   {:rpc_action, :meta_res, T.Res},
                   :total_2,
                   "totalTwo",
                   {:metadata_field_names, :meta_res}
                 )
               ]
    end

    test "an attribute union's members are union_member slots" do
      owner = {:field, :attribute, :status, T.Res}

      assert views(manifest(), &(&1.kind == :union_member and &1.owner == owner))
             |> Enum.sort_by(& &1.raw) ==
               [
                 slot(:union_member, owner, :num, "num", :formatter),
                 slot(:union_member, owner, :text, "text", :formatter)
               ]
    end

    test "an action argument's union members are union_member slots" do
      owner = {:action_argument, :choice, :act, T.Res, [:act_res, :act_res_again]}

      assert views(manifest(), &(&1.kind == :union_member and &1.owner == owner))
             |> Enum.sort_by(& &1.raw) ==
               [
                 slot(:union_member, owner, :left, "left", :formatter),
                 slot(:union_member, owner, :right, "right", :formatter)
               ]
    end

    test "a route argument is a route_argument slot" do
      assert views(
               manifest(),
               &(&1.kind == :route_argument and &1.owner == {:route, :save, T.Controller})
             )
             |> Enum.sort_by(& &1.raw) ==
               [
                 slot(:route_argument, {:route, :save, T.Controller}, :mode, "mode", :formatter),
                 slot(:route_argument, {:route, :save, T.Controller}, :opts, "opts", :formatter)
               ]
    end

    test "an inline map field is a type_field slot" do
      assert views(manifest(), raw_is(:hint)) ==
               [
                 slot(
                   :type_field,
                   {:action_argument, :extra, :create, T.Res, @res_rpc},
                   :hint,
                   "hint",
                   :formatter
                 )
               ]
    end

    test "a map entry field is a type_field slot under its type" do
      assert views(manifest(), raw_is(:alpha)) ==
               [slot(:type_field, {:type, T.Swatch}, :alpha, "alpha", :formatter)]
    end
  end

  # ── shapes carried over from the old tests ───────────────────────

  describe "shapes carried over" do
    test "W-c1 a calculation and an aggregate yield resource_field slots" do
      # verify_field_names_test: rejects calculation / aggregate with question mark ...
      kinds =
        manifest() |> client_slots(&(&1.raw in [:shout, :child_count])) |> Enum.map(& &1.kind)

      assert kinds == [:resource_field, :resource_field]
    end

    test "W-c2 an attribute union's members yield union_member slots under the resource" do
      # verify_field_names_test: the three union member cases;
      # verify_map_field_names_test: detects invalid field names in union type members
      slots = client_slots(manifest(), &(&1.kind == :union_member))
      assert {:field, :attribute, :status, T.Res} in Enum.map(slots, & &1.owner)
    end

    test "W-c3 inline map, keyword and tuple attributes yield type_field slots under the resource" do
      # verify_map_field_names_test: map, keyword and tuple type constraints
      for {attr, raws} <- [settings: [:choice, :nested, :theme], prefs: [:lang], pair: [:x, :y]] do
        owner = {:field, :attribute, attr, T.Res}

        assert manifest()
               |> client_slots(&(&1.owner == owner and &1.path == []))
               |> Enum.map(&{&1.kind, &1.raw})
               |> Enum.sort() == Enum.map(raws, &{:type_field, &1})
      end
    end

    test "W-c4 a calculation's inline map return yields type_field slots" do
      # verify_map_field_names_test: detects invalid field names in calculation return types
      assert views(manifest(), raw_is(:total)) ==
               [
                 slot(
                   :type_field,
                   {:field, :calculation, :summary, T.Res},
                   :total,
                   "total",
                   :formatter
                 )
               ]
    end

    test "W-c5 an array-of-map attribute's fields have the path entries[]" do
      # verify_map_field_names_test: ... inside array-of-map field constraints
      assert views(
               manifest(),
               &(&1.raw == :label and &1.owner == {:field, :attribute, :entries, T.Res})
             ) ==
               [
                 slot(
                   :type_field,
                   {:field, :attribute, :entries, T.Res},
                   :label,
                   "label",
                   :formatter,
                   ["[]"]
                 )
               ]
    end

    test "W-c6 a NewType's typescript_field_names/0 gives explicit slots under Type, the rest formatter slots" do
      # verify_map_field_names_test: the two NewType typescript_field_names/0 cases
      assert views(manifest(), owned_by({:type, T.Flags})) |> Enum.sort_by(& &1.raw) ==
               [
                 slot(
                   :type_field,
                   {:type, T.Flags},
                   :is_on?,
                   "isOn",
                   {:typescript_field_names, T.Flags}
                 ),
                 slot(:type_field, {:type, T.Flags}, :plain, "plain", :formatter)
               ]
    end

    test "W-c7 a nested map, keyword, union-in-map and deep nesting yield slots with the full path" do
      # verify_nested_map_field_names_test: the four cases
      owner = {:field, :attribute, :settings, T.Res}

      assert manifest()
             |> client_slots(&(&1.owner == owner and &1.path != []))
             |> Enum.map(&{&1.kind, &1.path, &1.raw})
             |> Enum.sort() ==
               [
                 {:type_field, ["nested"], :depth},
                 {:union_member, ["choice"], :long},
                 {:union_member, ["choice"], :short}
               ]
    end

    test "W-c8 a NewType over a primitive yields no type_field slot" do
      # verify_map_field_names_test: passes for a NewType whose subtype is a primitive
      assert [_] =
               client_slots(manifest(), &(&1.kind == :resource_field and &1.raw == :score))

      assert client_slots(
               manifest(),
               &(&1.owner in [{:type, T.Score}, {:field, :attribute, :score, T.Res}])
             ) ==
               []
    end

    test "W-c9 a route returns' nested fields have the path [].address" do
      # verify_typed_controller_test: rejects returns field names with question marks;
      # rejects field names nested in arrays and typed maps, reporting their path
      assert views(manifest(), raw_is(:line)) ==
               [
                 slot(
                   :type_field,
                   {:route_returns, :save, T.Controller},
                   :line,
                   "line",
                   :formatter,
                   ["[]", "address"]
                 )
               ]
    end

    test "W-c10 a route argument's inline map fields are type_field slots under the route" do
      # verify_typed_controller_test: rejects invalid field names in argument types
      assert views(manifest(), raw_is(:level)) ==
               [
                 slot(
                   :type_field,
                   {:route_argument, :opts, :save, T.Controller},
                   :level,
                   "level",
                   :formatter
                 )
               ]
    end

    test "W-c11 a route returning a NewType with typescript_field_names/0 gives explicit slots under Type" do
      # verify_typed_controller_test: honors typescript_field_names on types ...;
      # points at the mapping when a mapped field name is invalid
      assert client_slots(manifest(), &(&1.owner == {:route_returns, :flags, T.Controller})) == []
      assert Enum.any?(client_slots(manifest(), owned_by({:type, T.Flags})), &(&1.raw == :is_on?))
    end

    test "W-c12 route return fields are slots under their raw names" do
      # verify_typed_controller_test: rejects field names that are not valid identifiers
      assert views(manifest(), raw_is(:first_name)) ==
               [
                 slot(
                   :type_field,
                   {:route_returns, :save, T.Controller},
                   :first_name,
                   "firstName",
                   :formatter,
                   ["[]"]
                 )
               ]
    end

    test "W-c13 a map entry field with client_name has source {:client_name, Mod}" do
      # custom_types_dsl_test: a client_name that isn't a TypeScript identifier is rejected
      assert views(manifest(), raw_is(:hex)) ==
               [slot(:type_field, {:type, T.Swatch}, :hex, "hexCode", {:client_name, T.Swatch})]
    end

    test "W-c14 a field_names value has source {:field_names, Resource}" do
      # VerifyMappedFieldNames' value rule
      assert views(manifest(), raw_is(:line_1)) ==
               [
                 slot(
                   :resource_field,
                   {:resource, T.Res},
                   :line_1,
                   "lineOne",
                   {:field_names, T.Res}
                 )
               ]
    end

    test "a field_names value for a key that isn't an identifier has source {:field_names, Resource}" do
      manifest = InlineManifest.build!(domains: [T.DashMappedDomain])

      assert views(manifest, raw_is(:"attr-dash")) ==
               [
                 slot(
                   :resource_field,
                   {:resource, T.DashMappedRes},
                   :"attr-dash",
                   "attrDash",
                   {:field_names, T.DashMappedRes}
                 )
               ]
    end
  end

  # ── once per slot ────────────────────────────────────────────────

  describe "once per slot" do
    test "a NewType used as attribute, argument and route return gives one slot set, under Type" do
      flags = client_slots(manifest(), &(&1.raw in [:is_on?, :plain]))
      assert Enum.map(flags, & &1.owner) |> Enum.uniq() == [{:type, T.Flags}]
      assert length(flags) == 2
    end

    test "an inline map through an accepted attribute gives slots only under the resource" do
      assert manifest() |> client_slots(raw_is(:theme)) |> Enum.map(& &1.owner) ==
               [{:field, :attribute, :settings, T.Res}]
    end

    test "an action behind two rpc_actions gives argument slots once, listing both RPC names" do
      assert manifest() |> client_slots(raw_is(:code_1)) |> Enum.map(& &1.owner) ==
               [{:action, :act, T.Res, [:act_res, :act_res_again]}]
    end

    test "an inline :struct with instance_of declares its fields by its instance_of module" do
      assert manifest()
             |> client_slots(&(&1.owner == {:field, :attribute, :tagged, T.Res}))
             |> Enum.map(&{&1.raw, &1.container})
             |> Enum.sort() == [hex_code: {:module, T.Tagged}, label: {:module, T.Tagged}]
    end

    test "inline fields are declared :inline, a definition's by its module or map entry" do
      containers =
        manifest()
        |> client_slots(&(&1.kind == :type_field))
        |> Map.new(&{&1.raw, &1.container})

      assert containers.theme == :inline
      assert containers.plain == {:module, T.Flags}
      assert containers.alpha == {:map_entry, T.Swatch}
    end

    test "an inline :struct with instance_of gives source {:typescript_field_names, InstanceOf}" do
      assert views(manifest(), raw_is(:hex_code)) ==
               [
                 slot(
                   :type_field,
                   {:field, :attribute, :tagged, T.Res},
                   :hex_code,
                   "hexCode",
                   {:typescript_field_names, T.Tagged}
                 )
               ]
    end
  end

  # ── formatters ───────────────────────────────────────────────────

  describe "formatters" do
    defp client_name_of(manifest, %{kind: :resource_field, owner: {:resource, r}, raw: raw}),
      do: ClientNames.resource_field(resource(manifest, r), raw)

    defp client_name_of(
           manifest,
           %{kind: :calculation_argument, owner: {:calculation, c, r}} = s
         ),
         do: ClientNames.calculation_argument(resource(manifest, r), c, s.raw)

    defp client_name_of(manifest, %{kind: :action_argument, owner: {:action, a, r, _}} = s) do
      action =
        Enum.find_value(
          manifest.entrypoints,
          &(&1.resource == r and &1.action.name == a and &1.action)
        )

      ClientNames.action_input(resource(manifest, r), action, s.raw)
    end

    defp client_name_of(manifest, %{kind: :metadata_field, owner: {:rpc_action, rpc, _}} = s) do
      entrypoint = manifest |> AshRpc.Manifest.entrypoint_lookup() |> Map.fetch!(to_string(rpc))
      ClientNames.metadata_field(entrypoint, s.raw)
    end

    defp client_name_of(manifest, %{kind: :route_argument, owner: {:route, route, source}} = s) do
      Custom.route(manifest, source, route).inputs
      |> Enum.find(&(&1.name == s.raw))
      |> Map.fetch!(:client_name)
    end

    defp client_name_of(manifest, %{kind: kind} = s) when kind in [:type_field, :union_member] do
      {_owner, _path, node} =
        manifest
        |> AshTypescript.Manifest.TypeUses.positions()
        |> Enum.find(fn {owner, path, node} ->
          node_owner(owner) == s.owner and path == s.path and s.raw in node_keys(kind, node)
        end)

      if kind == :type_field,
        do: ClientNames.type_field(node, s.raw),
        else: ClientNames.union_member(node, s.raw)
    end

    defp client_name_of(manifest, %{kind: :static_field, raw: raw}),
      do: AshRpc.FieldFormatter.format_field_name(raw, AshRpc.Manifest.output_formatter(manifest))

    defp node_owner({:type, _} = owner), do: owner
    defp node_owner(owner), do: owner

    defp node_keys(:type_field, node), do: Map.keys(AshRpc.Manifest.Custom.type_field_names(node))

    defp node_keys(:union_member, node),
      do: Map.keys(AshRpc.Manifest.Custom.type_member_names(node))

    defp resource(manifest, module),
      do: Map.fetch!(AshRpc.Manifest.resource_lookup(manifest), module)

    for formatter <- [:snake_case, :pascal_case, {AshTypescript.Test.Formatters, :custom_format}] do
      test "under #{inspect(formatter)}, each client slot's name is ClientNames' name" do
        manifest =
          AshTypescript.Manifest.redecorate(manifest(),
            output_formatter: unquote(Macro.escape(formatter))
          )

        slots = client_slots(manifest, fn _ -> true end)
        assert slots != []

        for slot <- slots do
          assert slot.name == client_name_of(manifest, slot), inspect(view(slot))
        end
      end
    end
  end

  defmodule WeirdFormatter do
    @moduledoc false
    # Turns has_more into a name that isn't an identifier, the rest camelCase.
    def weird(name) do
      case to_string(name) do
        "has_more" -> "has-more"
        other -> AshRpc.FieldFormatter.format_field_name(other, :camel_case)
      end
    end
  end

  describe "static vocabulary" do
    test "each static key is a client slot under the formatter, owner :static" do
      static = manifest() |> client_slots(&(&1.owner == :static)) |> Enum.map(&view/1)

      assert Enum.sort(Enum.map(static, & &1.raw)) ==
               Enum.sort(AshTypescript.Helpers.static_client_names())

      assert slot(:static_field, :static, :has_more, "hasMore", :formatter) in static
      assert slot(:static_field, :static, :fetch_options, "fetchOptions", :formatter) in static
    end

    test "Helpers' formatted_*_field/0 names are static keys" do
      names = AshTypescript.Helpers.static_client_names()

      for {fun, 0} <- AshTypescript.Helpers.__info__(:functions),
          name = to_string(fun),
          String.starts_with?(name, "formatted_") and String.ends_with?(name, "_field") do
        assert Enum.any?(
                 names,
                 &(AshTypescript.Helpers.format_output_field(&1) ==
                     apply(AshTypescript.Helpers, fun, []))
               ),
               "#{fun}/0 isn't a static key"
      end
    end

    test "a custom formatter's bad static names are reported" do
      manifest =
        AshTypescript.Manifest.redecorate(manifest(),
          output_formatter: {T.WeirdFormatter, :weird, []}
        )

      problems =
        manifest
        |> NameCheck.problems(Custom.custom_types(manifest))
        |> Enum.filter(&(&1.slot.owner == :static))

      assert [%{reason: :not_identifier, slot: %{raw: :has_more, name: "has-more"}} = problem] =
               problems

      assert NameCheck.describe(problem) ==
               ~s[- key :has_more → "has-more" (formatted), not an identifier: the ] <>
                 ~s[output_field_formatter turns it into "has-more": change the formatter]
    end

    for formatter <- [:camel_case, :snake_case, :pascal_case] do
      test "the #{inspect(formatter)} formatter gives no static problem" do
        manifest =
          AshTypescript.Manifest.redecorate(manifest(), output_formatter: unquote(formatter))

        assert manifest
               |> NameCheck.problems(Custom.custom_types(manifest))
               |> Enum.filter(&(&1.slot.owner == :static)) == []
      end
    end
  end

  # ── the probe's gaps, reach, the test app ────────────────────────

  # The probe's gap fixtures use valid names, so they compile now that the
  # client family is checked; `inject/2` puts the probe's bad names into the
  # decorated manifest (`@client_gaps`). The bad names compiled as they are
  # are the "end to end" tests'.

  defmodule GapEmb do
    @moduledoc false
    use Ash.Resource, data_layer: :embedded, extensions: [AshTypescript.Resource]

    typescript do
      type_name "NameCheckGapEmb"
    end

    attributes do
      attribute :emb_dash, :string, public?: true
    end
  end

  defmodule GapRes do
    @moduledoc false
    use Ash.Resource,
      domain: AshTypescript.Manifest.NameCheckTest.GapDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "NameCheckGapRes"
    end

    attributes do
      uuid_primary_key :id
      attribute :attr_dash, :string, public?: true
      attribute :emb, AshTypescript.Manifest.NameCheckTest.GapEmb, public?: true

      attribute :u, :union,
        public?: true,
        constraints: [types: [member_dash: [type: :string]]]
    end

    calculations do
      calculate :c, :string, expr("x") do
        public? true
        argument :calc_arg_dash, :string
        argument :calc_arg_q, :string
      end
    end

    actions do
      defaults [:read]

      action :act, :string do
        argument :arg_dash, :string

        argument :u2, :union,
          constraints: [types: [m2_dash: [type: :string], m2_okq: [type: :integer]]]

        run fn _input, _context -> {:ok, "x"} end
      end

      read :meta do
        metadata :meta_dash, :string
      end
    end
  end

  defmodule GapDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Manifest.NameCheckTest.GapRes do
        rpc_action :list_gap, :read
        rpc_action :act_gap, :act
        rpc_action :meta_gap, :meta, show_metadata: [:meta_dash]
      end
    end

    resources do
      resource AshTypescript.Manifest.NameCheckTest.GapRes
    end
  end

  defmodule Unreached do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "NameCheckUnreached"
    end

    attributes do
      uuid_primary_key :id
      attribute :lonely, :string, public?: true
    end
  end

  describe "reach and the test app" do
    test "undecorated resources have no slots" do
      owners = manifest() |> client_slots(fn _ -> true end) |> Enum.map(& &1.owner)
      refute {:resource, T.Unreached} in owners
      refute Enum.any?(manifest() |> client_slots(fn _ -> true end), &(&1.raw == :lonely))
    end

    test "the test app manifest has no client problems" do
      manifest = AshTypescript.manifest()

      assert manifest
             |> NameCheck.problems(Custom.custom_types(manifest))
             |> Enum.filter(&(&1.slot.family == :client)) == []
    end
  end

  # ── binding slots ────────────────────────────────────────────────

  defp binding_views(manifest, owner) do
    manifest
    |> slots()
    |> Enum.filter(&(&1.family == :binding and &1.owner == owner))
    |> Enum.map(&Map.take(&1, [:kind, :role, :raw, :name, :bare?, :source]))
  end

  defp binding(kind, role, raw, name, bare?, source \\ :formatter),
    do: %{kind: kind, role: role, raw: raw, name: name, bare?: bare?, source: source}

  describe "binding slots, per kind" do
    test "each binding slot is bound as a value or as a type" do
      bound_as =
        manifest()
        |> slots()
        |> Enum.filter(&(&1.family == :binding))
        |> Enum.map(&{&1.kind, &1.role, &1.bound_as})
        |> Enum.uniq()
        |> Enum.sort()

      assert bound_as == [
               {:route_function, :function, :value},
               {:route_function, :input_type, :type},
               {:route_function, :path, :value},
               {:route_function, :result_type, :type},
               {:route_schema, :valibot_schema, :value},
               {:route_schema, :zod_schema, :value},
               {:rpc_function, :channel, :value},
               {:rpc_function, :execution, :value},
               {:rpc_function, :input_type, :type},
               {:rpc_function, :valibot_schema, :value},
               {:rpc_function, :validation, :value},
               {:rpc_function, :validation_channel, :value},
               {:rpc_function, :zod_schema, :value},
               {:typed_query_const, :const, :value},
               {:typed_query_const, :result_type, :type}
             ]
    end

    test "an rpc_action gives its seven slots" do
      assert binding_views(manifest(), {:rpc_action, :list_res, T.Domain}) ==
               [
                 binding(:rpc_function, :execution, :list_res, "listRes", true),
                 binding(:rpc_function, :validation, :list_res, "validateListRes", false),
                 binding(:rpc_function, :channel, :list_res, "listResChannel", false),
                 binding(
                   :rpc_function,
                   :validation_channel,
                   :list_res,
                   "validateListResChannel",
                   false
                 ),
                 binding(:rpc_function, :input_type, :list_res, "ListResInput", false),
                 binding(:rpc_function, :zod_schema, :list_res, "listResZodSchema", false),
                 binding(:rpc_function, :valibot_schema, :list_res, "listResValibotSchema", false)
               ]
    end

    test "a typed query gives its const and its result type" do
      assert binding_views(manifest(), {:typed_query, :child_page, T.Domain}) ==
               [
                 binding(:typed_query_const, :const, :child_page, "childPage", true),
                 binding(:typed_query_const, :result_type, :child_page, "ChildPageResult", false)
               ]
    end

    test "ts_fields_const_name and ts_result_type_name are the slots' {:option, …} sources" do
      assert binding_views(manifest(), {:typed_query, :child_named, T.Domain}) ==
               [
                 binding(
                   :typed_query_const,
                   :const,
                   :child_named,
                   "childNamedFields",
                   true,
                   {:option, :ts_fields_const_name}
                 ),
                 binding(
                   :typed_query_const,
                   :result_type,
                   :child_named,
                   "ChildNamedResult",
                   false,
                   {:option, :ts_result_type_name}
                 )
               ]
    end

    test "a route with arguments gives four route_function and two route_schema slots" do
      assert binding_views(manifest(), {:route, :save, T.Controller}) ==
               [
                 binding(:route_function, :function, :save, "save", true),
                 binding(:route_function, :path, :save, "savePath", false),
                 binding(:route_function, :input_type, :save, "SaveInput", false),
                 binding(:route_function, :result_type, :save, "SaveResult", false),
                 binding(:route_schema, :zod_schema, :save, "saveZodSchema", false),
                 binding(:route_schema, :valibot_schema, :save, "saveValibotSchema", false)
               ]
    end

    test "a route without arguments has no route_schema slot" do
      kinds = manifest() |> binding_views({:route, :flags, T.Controller}) |> Enum.map(& &1.kind)
      assert Enum.uniq(kinds) == [:route_function]
    end

    test "schema-name overrides give source {:option, :zod_schema_name}" do
      schemas =
        manifest()
        |> binding_views({:route, :login, T.Controller})
        |> Enum.filter(&(&1.kind == :route_schema))

      assert schemas == [
               binding(
                 :route_schema,
                 :zod_schema,
                 :login,
                 "loginRouteZod",
                 false,
                 {:option, :zod_schema_name}
               ),
               binding(
                 :route_schema,
                 :valibot_schema,
                 :login,
                 "loginRouteValibot",
                 false,
                 {:option, :valibot_schema_name}
               )
             ]
    end

    test "W-b1 a route's raw name is carried on its slots" do
      # verify_typed_controller_test: rejects route names with underscore-number
      # patterns; the reserved and near-reserved route cases
      raws = manifest() |> binding_views({:route, :save, T.Controller}) |> Enum.map(& &1.raw)
      assert Enum.uniq(raws) == [:save]
    end

    test "slots don't depend on feature flags" do
      # The test config generates no channel functions for these actions, and
      # every slot is there all the same.
      roles =
        manifest() |> binding_views({:rpc_action, :act_res, T.Domain}) |> Enum.map(& &1.role)

      assert roles ==
               [:execution, :validation, :channel, :validation_channel, :input_type] ++
                 [:zod_schema, :valibot_schema]
    end
  end

  defmodule BindingGapRes do
    @moduledoc false
    use Ash.Resource,
      domain: AshTypescript.Manifest.NameCheckTest.BindingGapDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "NameCheckBindingGapRes"
    end

    attributes do
      uuid_primary_key :id
    end

    actions do
      defaults [:read]
    end
  end

  defmodule BindingGapDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Manifest.NameCheckTest.BindingGapRes do
        rpc_action :list_todos_gap, :read

        typed_query :dashboard, :read do
          ts_fields_const_name "dashBoard"
          ts_result_type_name "DashResult"
          fields [:id]
        end
      end
    end

    resources do
      resource AshTypescript.Manifest.NameCheckTest.BindingGapRes
    end
  end

  defmodule BindingGapController do
    @moduledoc false
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.Test.NameCheckBindingGapController

      post :login do
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
        argument :code, :string
        zod_schema_name "loginSchema"
      end
    end
  end

  describe "typed channel publications" do
    alias AshTypescript.Test.PublicationFixtures.{Feed, FeedChannel}

    defp feed_manifest, do: InlineManifest.build!(typed_channels: [FeedChannel])

    test "a publication's event is a key slot and its payload type a type slot" do
      assert binding_views(feed_manifest(), {:publication, "item_pushed", Feed, FeedChannel}) ==
               [
                 binding(:channel_event, :event, "item_pushed", "item_pushed", false),
                 binding(:channel_event, :payload_type, "item_pushed", "ItemPushedPayload", false)
               ]

      bound_as =
        for slot <- slots(feed_manifest()),
            slot.kind == :channel_event,
            uniq: true,
            do: {slot.role, slot.bound_as}

      assert Enum.sort(bound_as) == [event: :key, payload_type: :type]
    end

    test "an event that isn't an identifier is a problem, its payload type a derived one" do
      manifest = inject(feed_manifest(), %{"item_pushed" => "item-pushed"})

      problems =
        manifest
        |> NameCheck.problems(Custom.custom_types(manifest))
        |> Enum.map(&{&1.slot.kind, &1.slot.role, &1.slot.name, &1.reason})

      assert problems == [
               {:channel_event, :event, "item-pushed", :not_identifier},
               {:channel_event, :payload_type, "Item-pushedPayload", :not_identifier}
             ]
    end

    test "the payload type name is TypedChannel.Codegen's" do
      assert AshTypescript.TypedChannel.Codegen.payload_type_name("item_pushed") ==
               "ItemPushedPayload"
    end
  end

  describe "binding reach and the test app" do
    test "the probe's binding gaps are slots, and problems/2 lists them" do
      manifest =
        [domains: [T.BindingGapDomain], typed_controllers: [T.BindingGapController]]
        |> InlineManifest.build!()
        |> inject(@binding_gaps)

      names =
        manifest
        |> NameCheck.problems(Custom.custom_types(manifest))
        |> Enum.filter(&(&1.slot.family == :binding))
        |> Enum.map(& &1.slot.name)

      for name <- ["list-todos", "dash-board", "Dash-Result", "login-schema"] do
        assert name in names
      end
    end

    test "the raw-name rule applies once per owner, on its bare slot" do
      # VerifyRpc still rejects `rpc_action :list_1` at compile, so the raw
      # name is set on a compiled manifest's entrypoint.
      manifest = manifest()

      entrypoints =
        Enum.map(manifest.entrypoints, fn entrypoint ->
          case Custom.rpc_action(entrypoint) do
            %{name: :list_res} = rpc_action ->
              put_in(entrypoint.custom.ash_typescript.rpc_action, %{rpc_action | name: :list_1})

            _other ->
              entrypoint
          end
        end)

      problems =
        %{manifest | entrypoints: entrypoints}
        |> NameCheck.problems(Custom.custom_types(manifest))
        |> Enum.filter(&(&1.slot.family == :binding))
        |> Enum.map(&{&1.slot.role, &1.slot.name, &1.reason})

      assert problems == [{:execution, "list1", :invalid_raw_name}]
    end

    test "the test app manifest has no binding problems" do
      manifest = AshTypescript.manifest()

      assert manifest
             |> NameCheck.problems(Custom.custom_types(manifest))
             |> Enum.filter(&(&1.slot.family == :binding)) == []
    end
  end

  # ── alias slots ──────────────────────────────────────────────────

  defmodule AliasPoint do
    @moduledoc false
    use AshTypescript.Test.PassThroughType
  end

  defmodule AliasPlain do
    @moduledoc false
    use AshTypescript.Test.PassThroughType
  end

  defmodule AliasCode do
    @moduledoc false
    use AshTypescript.Test.PassThroughType, storage: :string
  end

  defmodule AliasTyped do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
      field :a, :string
    end
  end

  defmodule CallbackMap do
    @moduledoc false
    use Ash.TypedStruct

    def typescript_type_alias, do: "CallbackMap"

    typed_struct do
      field :a, :string
    end
  end

  defmodule CallbackScalar do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: :string

    def typescript_type_alias,
      do: :persistent_term.get({__MODULE__, :alias}, "CallbackScalar")
  end

  defmodule AliasRes do
    @moduledoc false
    use Ash.Resource,
      domain: AshTypescript.Manifest.NameCheckTest.AliasDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "NameCheckAliasRes"
    end

    attributes do
      uuid_primary_key :id
      attribute :point, AshTypescript.Manifest.NameCheckTest.AliasPoint, public?: true
      attribute :plain, AshTypescript.Manifest.NameCheckTest.AliasPlain, public?: true
      attribute :code, AshTypescript.Manifest.NameCheckTest.AliasCode, public?: true
      attribute :other_code, AshTypescript.Manifest.NameCheckTest.AliasCode, public?: true
      attribute :typed, AshTypescript.Manifest.NameCheckTest.AliasTyped, public?: true
      attribute :callback_map, AshTypescript.Manifest.NameCheckTest.CallbackMap, public?: true

      attribute :callback_scalar, AshTypescript.Manifest.NameCheckTest.CallbackScalar,
        public?: true

      attribute :ulid, AshDoubleEntry.ULID, public?: true
      attribute :external, AshTypescript.Test.ExternalCode, public?: true
    end

    actions do
      defaults [:read]

      action :by_code, :string do
        argument :code, AshTypescript.Manifest.NameCheckTest.AliasCode
        run fn _input, _context -> {:ok, "x"} end
      end
    end
  end

  defmodule AliasDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Manifest.NameCheckTest.AliasRes do
        rpc_action :list_alias, :read
        rpc_action :by_code, :by_code
      end
    end

    resources do
      resource AshTypescript.Manifest.NameCheckTest.AliasRes
    end
  end

  @alias_entries [
    quote do
      map AshTypescript.Manifest.NameCheckTest.AliasPoint do
        ts_alias "AliasPoint"
        field :lat, :float
      end
    end,
    quote do
      map AshTypescript.Manifest.NameCheckTest.AliasPlain do
        field :lat, :float
      end
    end,
    quote do
      scalar AshTypescript.Manifest.NameCheckTest.AliasCode, :string do
        ts_alias "AliasCode"
      end
    end,
    quote do
      map AshTypescript.Manifest.NameCheckTest.AliasTyped, ts_alias: "AliasTyped"
    end,
    quote do
      map SomeLib.NameCheckUnreached do
        ts_alias "Unreached"
        field :x, :string
      end
    end
  ]

  defp alias_manifest do
    InlineManifest.build!(
      domains: [T.AliasDomain],
      body: InlineManifest.app_custom_types(@alias_entries)
    )
  end

  defp alias_views(manifest) do
    manifest
    |> slots()
    |> Enum.filter(&(&1.family == :alias))
    |> Enum.map(&Map.take(&1, [:kind, :owner, :raw, :name, :source]))
  end

  defp alias_slot(kind, module, name, source),
    do: %{kind: kind, owner: {:type, module}, raw: module, name: name, source: source}

  describe "alias slots" do
    test "W-a1 a reached map entry's ts_alias is a map_alias slot with source {:ts_alias, Mod}" do
      # custom_type_names_test: the map-alias cases
      assert alias_slot(:map_alias, T.AliasPoint, "AliasPoint", {:ts_alias, T.AliasPoint}) in alias_views(
               alias_manifest()
             )
    end

    test "a map entry without ts_alias is a map_alias slot with source :module_name" do
      assert alias_slot(
               :map_alias,
               T.AliasPlain,
               "AshTypescriptManifestNameCheckTestAliasPlain",
               :module_name
             ) in alias_views(alias_manifest())
    end

    test "W-a2 a reached scalar entry's ts_alias is a scalar_alias slot" do
      # type_alias_dsl_test: the scalar ts_alias cases
      assert alias_slot(:scalar_alias, T.AliasCode, "AliasCode", {:ts_alias, T.AliasCode}) in alias_views(
               alias_manifest()
             )
    end

    test "W-a3 a field-less entry's ts_alias is a map_alias slot" do
      # type_alias_dsl_test: a field-less entry's ts_alias is checked
      assert alias_slot(:map_alias, T.AliasTyped, "AliasTyped", {:ts_alias, T.AliasTyped}) in alias_views(
               alias_manifest()
             )
    end

    test "W-a4 a typescript_type_alias/0 is a slot with source {:typescript_type_alias, Mod}" do
      # custom_type_names_test / type_alias_names_test: the callback cases
      views = alias_views(alias_manifest())

      assert alias_slot(
               :map_alias,
               T.CallbackMap,
               "CallbackMap",
               {:typescript_type_alias, T.CallbackMap}
             ) in views

      assert alias_slot(
               :scalar_alias,
               T.CallbackScalar,
               "CallbackScalar",
               {:typescript_type_alias, T.CallbackScalar}
             ) in views
    end

    test "W-a5 an unreached custom_types entry has no slot" do
      # decision unreached-names: SomeLib.* entries, and the app entries this
      # manifest doesn't reach
      raws = alias_manifest() |> alias_views() |> Enum.map(& &1.raw)
      refute SomeLib.NameCheckUnreached in raws
      refute AshTypescript.Test.GeoPoint in raws
      refute AshTypescript.Test.CustomIdentifier in raws
    end

    test "a built-in scalar alias is a slot with source {:builtin, Mod}" do
      assert alias_slot(
               :scalar_alias,
               AshDoubleEntry.ULID,
               "ULID",
               {:builtin, AshDoubleEntry.ULID}
             ) in alias_views(alias_manifest())
    end

    test "MFA ts_alias results aren't slots" do
      refute AshTypescript.Test.ExternalCode in (alias_manifest()
                                                 |> alias_views()
                                                 |> Enum.map(& &1.raw))
    end

    test "a scalar used in several places is one slot" do
      assert alias_manifest() |> alias_views() |> Enum.count(&(&1.raw == T.AliasCode)) == 1
    end

    test "the test app manifest has no alias problems" do
      manifest = AshTypescript.manifest()

      assert manifest
             |> NameCheck.problems(Custom.custom_types(manifest))
             |> Enum.filter(&(&1.slot.family == :alias)) == []
    end

    test "a callback alias flipped to a reserved word after the compile is a problem" do
      manifest = alias_manifest()
      :persistent_term.put({T.CallbackScalar, :alias}, "class")
      on_exit(fn -> :persistent_term.erase({T.CallbackScalar, :alias}) end)

      problems =
        manifest
        |> NameCheck.problems(Custom.custom_types(manifest))
        |> Enum.filter(&(&1.slot.family == :alias))

      assert [%{reason: reason}] = problems

      assert reason ==
               {:alias,
                ~s[The typescript_type_alias/0 result "class" of #{inspect(T.CallbackScalar)} ] <>
                  "is a TypeScript reserved word."}
    end
  end

  # ── describe/1 and the report ────────────────────────────────────

  defp problem(fields, reason) do
    slot =
      Map.merge(
        %{
          family: :client,
          path: [],
          bare?: false,
          source: :formatter,
          formatter: :camel_case,
          container: :inline
        },
        Map.new(fields)
      )

    %{slot: slot, reason: reason}
  end

  describe "describe/1, client names" do
    test "resource field, :formatter" do
      assert NameCheck.describe(
               problem(
                 [
                   kind: :resource_field,
                   owner: {:resource, T.Res},
                   raw: :is_done?,
                   name: "isDone?"
                 ],
                 :not_identifier
               )
             ) ==
               ~s[- field :is_done? → "isDone?" (formatted), not an identifier: add it to ] <>
                 ~s[field_names in the resource's typescript block, e.g. is_done?: "isDone"]
    end

    test "resource field, :formatter, underscore before a digit" do
      assert NameCheck.describe(
               problem(
                 [
                   kind: :resource_field,
                   owner: {:resource, T.Res},
                   raw: :address_line_1,
                   name: "addressLine1"
                 ],
                 :digit_after_underscore
               )
             ) ==
               ~s[- field :address_line_1 → "addressLine1" (formatted), underscore before a ] <>
                 ~s[digit: add it to field_names in the resource's typescript block, e.g. ] <>
                 ~s[address_line_1: "addressLine1"]
    end

    test "resource field, :formatter, a resource without the AshTypescript.Resource extension" do
      assert NameCheck.describe(
               problem(
                 [
                   kind: :resource_field,
                   owner: {:resource, T.Res},
                   raw: :is_done?,
                   name: "isDone?",
                   exposed?: false
                 ],
                 :not_identifier
               )
             ) ==
               ~s[- field :is_done? → "isDone?" (formatted), not an identifier: add the ] <>
                 "AshTypescript.Resource extension and a field_names entry, e.g. " <>
                 ~s[is_done?: "isDone", or rename it]
    end

    test "a name the output_field_formatter made from a usable raw name" do
      for {kind, owner, fix} <- [
            {:resource_field, {:resource, T.Res}, "change the formatter"},
            {:calculation_argument, {:calculation, :preview, T.Res}, "change the formatter"},
            {:union_member, {:field, :attribute, :content, T.Res}, "change the formatter"},
            {:type_field, {:type, T.Flags}, "change the formatter"},
            {:route_argument, {:route, :test, T.Controller}, "change the formatter"},
            {:action_argument, {:action, :create, T.Res, [:create_todo]},
             "change the formatter, or map it with argument_names"},
            {:metadata_field, {:rpc_action, :read_data, T.Res},
             "change the formatter, or map it with metadata_field_names"}
          ] do
        line =
          NameCheck.describe(
            problem(
              [
                kind: kind,
                owner: owner,
                raw: :title,
                name: "ti-tle",
                formatter: {M, :f, []},
                container: {:module, T.Flags}
              ],
              :not_identifier
            )
          )

        assert String.ends_with?(
                 line,
                 ~s[ → "ti-tle" (formatted), not an identifier: the output_field_formatter ] <>
                   ~s[turns it into "ti-tle": #{fix}]
               ),
               "#{kind}: #{line}"
      end
    end

    test "resource field, {:field_names, r}" do
      assert NameCheck.describe(
               problem(
                 [
                   kind: :resource_field,
                   owner: {:resource, T.Res},
                   raw: :is_done?,
                   name: "is-done",
                   source: {:field_names, T.Res}
                 ],
                 :not_identifier
               )
             ) ==
               ~s[- field :is_done? → "is-done" (field_names), not an identifier: ] <>
                 "change the field_names value"
    end

    test "action argument, :formatter" do
      assert NameCheck.describe(
               problem(
                 [
                   kind: :action_argument,
                   owner: {:action, :create, T.Res, [:create_todo]},
                   raw: :"due-at",
                   name: "due-at"
                 ],
                 :not_identifier
               )
             ) ==
               ~s[- argument :"due-at" of action :create (RPC actions create_todo) → "due-at" ] <>
                 ~s[(formatted), not an identifier: add it to argument_names for the action, ] <>
                 ~s{e.g. create: ["due-at": "dueAt"]}
    end

    test "action argument, {:argument_names, …}" do
      assert NameCheck.describe(
               problem(
                 [
                   kind: :action_argument,
                   owner: {:action, :create, T.Res, [:create_todo]},
                   raw: :due_at?,
                   name: "due-at",
                   source: {:argument_names, T.Res, :create}
                 ],
                 :not_identifier
               )
             ) ==
               ~s[- argument :due_at? of action :create (RPC actions create_todo) → "due-at" ] <>
                 "(argument_names), not an identifier: change the argument_names value"
    end

    test "metadata, :formatter" do
      assert NameCheck.describe(
               problem(
                 [
                   kind: :metadata_field,
                   owner: {:rpc_action, :read_data, T.Res},
                   raw: :field_1,
                   name: "field1"
                 ],
                 :digit_after_underscore
               )
             ) ==
               ~s[- metadata :field_1 of RPC action :read_data → "field1" (formatted), ] <>
                 "underscore before a digit: add it to the RPC action's metadata_field_names, " <>
                 ~s[e.g. field_1: "field1"]
    end

    test "metadata, {:metadata_field_names, …}" do
      assert NameCheck.describe(
               problem(
                 [
                   kind: :metadata_field,
                   owner: {:rpc_action, :read_data, T.Res},
                   raw: :field_a,
                   name: "field-a",
                   source: {:metadata_field_names, :read_data}
                 ],
                 :not_identifier
               )
             ) ==
               ~s[- metadata :field_a of RPC action :read_data → "field-a" ] <>
                 "(metadata_field_names), not an identifier: change the metadata_field_names value"
    end

    test "type field, {:typescript_field_names, m}" do
      assert NameCheck.describe(
               problem(
                 [
                   kind: :type_field,
                   owner: {:type, T.Flags},
                   raw: :ok,
                   name: "ok?",
                   source: {:typescript_field_names, T.Flags},
                   container: {:module, T.Flags}
                 ],
                 :not_identifier
               )
             ) ==
               ~s[- field :ok → "ok?" (typescript_field_names/0), not an identifier: change ] <>
                 "#{inspect(T.Flags)}.typescript_field_names/0"
    end

    test "type field, {:client_name, m}" do
      assert NameCheck.describe(
               problem(
                 [
                   kind: :type_field,
                   owner: {:type, T.Swatch},
                   raw: :hex,
                   name: "hex-code",
                   source: {:client_name, T.Swatch},
                   container: {:map_entry, T.Swatch}
                 ],
                 :not_identifier
               )
             ) ==
               ~s[- field :hex → "hex-code" (client_name), not an identifier: change the ] <>
                 "field's client_name in the map entry"
    end

    test "type field, :formatter, map entry" do
      assert NameCheck.describe(
               problem(
                 [
                   kind: :type_field,
                   owner: {:type, T.Swatch},
                   raw: :is_on?,
                   name: "isOn?",
                   container: {:map_entry, T.Swatch}
                 ],
                 :not_identifier
               )
             ) ==
               ~s[- field :is_on? → "isOn?" (formatted), not an identifier: set client_name ] <>
                 ~s[on the field, e.g. client_name: "isOn"]
    end

    test "type field, :formatter, named module" do
      assert NameCheck.describe(
               problem(
                 [
                   kind: :type_field,
                   owner: {:type, T.Flags},
                   raw: :is_on?,
                   name: "isOn?",
                   container: {:module, T.Flags}
                 ],
                 :not_identifier
               )
             ) ==
               ~s[- field :is_on? → "isOn?" (formatted), not an identifier: add ] <>
                 "typescript_field_names/0 to #{inspect(T.Flags)}, e.g. is_on?: \"isOn\""
    end

    test "type field, :formatter, inline in a resource field or action type" do
      assert NameCheck.describe(
               problem(
                 [
                   kind: :type_field,
                   owner: {:field, :attribute, :entries, T.Res},
                   path: ["[]"],
                   raw: :entry_1,
                   name: "entry1"
                 ],
                 :digit_after_underscore
               )
             ) ==
               ~s{- field :entries[].entry_1 → "entry1" (formatted), underscore before a digit: } <>
                 "wrap it in an Ash.Type.NewType with typescript_field_names/0"
    end

    test "type field, :formatter, inline in an action argument names the action" do
      assert NameCheck.describe(
               problem(
                 [
                   kind: :type_field,
                   owner: {:action_argument, :data, :create, T.Res, [:create_todo]},
                   raw: :field_1,
                   name: "field1"
                 ],
                 :digit_after_underscore
               )
             ) ==
               ~s[- field :data.field_1 of action :create (RPC actions create_todo) → "field1" ] <>
                 "(formatted), underscore before a digit: wrap it in an Ash.Type.NewType with " <>
                 "typescript_field_names/0"
    end

    test "type field, :formatter, inline in a route" do
      assert NameCheck.describe(
               problem(
                 [
                   kind: :type_field,
                   owner: {:route_returns, :items, T.Controller},
                   path: ["[]", "address"],
                   raw: :line_1,
                   name: "line1"
                 ],
                 :digit_after_underscore
               )
             ) ==
               ~s{- field :returns[].address.line_1 → "line1" (formatted), underscore before a } <>
                 "digit: rename the field, e.g. :line1"
    end

    test "calculation argument" do
      assert NameCheck.describe(
               problem(
                 [
                   kind: :calculation_argument,
                   owner: {:calculation, :preview, T.Res},
                   raw: :page_2,
                   name: "page2"
                 ],
                 :digit_after_underscore
               )
             ) ==
               ~s[- argument :page_2 of calculation :preview → "page2" (formatted), underscore ] <>
                 "before a digit: rename it, e.g. :page2"
    end

    test "union member" do
      assert NameCheck.describe(
               problem(
                 [
                   kind: :union_member,
                   owner: {:field, :attribute, :content, T.Res},
                   raw: :has_html?,
                   name: "hasHtml?"
                 ],
                 :not_identifier
               )
             ) ==
               ~s[- member :content.has_html? → "hasHtml?" (formatted), not an identifier: ] <>
                 "rename it, e.g. :has_html"
    end

    test "route argument (verify_typed_controller_test: suggests better names in error message)" do
      assert NameCheck.describe(
               problem(
                 [
                   kind: :route_argument,
                   owner: {:route, :test, T.Controller},
                   raw: :address_line_1,
                   name: "addressLine1"
                 ],
                 :digit_after_underscore
               )
             ) ==
               ~s[- argument :address_line_1 → "addressLine1" (formatted), underscore before a ] <>
                 "digit: rename it, e.g. :address_line1"
    end
  end

  describe "describe/1, binding and alias names" do
    defp binding_problem(fields, reason),
      do: problem([family: :binding, container: nil] ++ fields, reason)

    test "rpc_function, :formatter, not an identifier" do
      assert NameCheck.describe(
               binding_problem(
                 [
                   kind: :rpc_function,
                   role: :execution,
                   owner: {:rpc_action, :"list-todos", T.Domain},
                   raw: :"list-todos",
                   name: "list-todos",
                   bare?: true
                 ],
                 :not_identifier
               )
             ) ==
               ~s[- function "list-todos", not an identifier: rename the rpc_action, e.g. :list_todos]
    end

    test "rpc_function, :formatter, a reserved word" do
      assert NameCheck.describe(
               binding_problem(
                 [
                   kind: :rpc_function,
                   role: :execution,
                   owner: {:rpc_action, :delete, T.Domain},
                   raw: :delete,
                   name: "delete",
                   bare?: true
                 ],
                 :reserved_word
               )
             ) ==
               ~s[- function "delete", a JavaScript reserved word: rename the rpc_action, ] <>
                 "for example :delete_item"
    end

    test "route_function and typed_query_const, :formatter" do
      assert NameCheck.describe(
               binding_problem(
                 [
                   kind: :route_function,
                   role: :function,
                   owner: {:route, :new, T.Controller},
                   raw: :new,
                   name: "new",
                   bare?: true
                 ],
                 :reserved_word
               )
             ) ==
               ~s[- function "new", a JavaScript reserved word: rename the route, for example :new_item]

      assert NameCheck.describe(
               binding_problem(
                 [
                   kind: :typed_query_const,
                   role: :const,
                   owner: {:typed_query, :new, T.Domain},
                   raw: :new,
                   name: "new",
                   bare?: true
                 ],
                 :reserved_word
               )
             ) ==
               ~s[- const "new", a JavaScript reserved word: rename the typed_query, for example :new_item, or set ts_fields_const_name]
    end

    test "typed_query_const, {:option, …}" do
      assert NameCheck.describe(
               binding_problem(
                 [
                   kind: :typed_query_const,
                   role: :const,
                   owner: {:typed_query, :dashboard, T.Domain},
                   raw: :dashboard,
                   name: "dash-board",
                   bare?: true,
                   source: {:option, :ts_fields_const_name}
                 ],
                 :not_identifier
               )
             ) ==
               ~s[- const "dash-board" (ts_fields_const_name), not an identifier: change ts_fields_const_name]

      assert NameCheck.describe(
               binding_problem(
                 [
                   kind: :typed_query_const,
                   role: :result_type,
                   owner: {:typed_query, :dashboard, T.Domain},
                   raw: :dashboard,
                   name: "Dash-Result",
                   source: {:option, :ts_result_type_name}
                 ],
                 :not_identifier
               )
             ) ==
               ~s[- result type "Dash-Result" (ts_result_type_name), not an identifier: change ts_result_type_name]
    end

    test "route_schema, {:option, …}" do
      assert NameCheck.describe(
               binding_problem(
                 [
                   kind: :route_schema,
                   role: :zod_schema,
                   owner: {:route, :login, T.Controller},
                   raw: :login,
                   name: "login-schema",
                   source: {:option, :zod_schema_name}
                 ],
                 :not_identifier
               )
             ) ==
               ~s[- zod schema "login-schema" (zod_schema_name), not an identifier: change zod_schema_name]
    end

    test "route_schema, :formatter" do
      assert NameCheck.describe(
               binding_problem(
                 [
                   kind: :route_schema,
                   role: :valibot_schema,
                   owner: {:route, :"log-in", T.Controller},
                   raw: :"log-in",
                   name: "log-inValibotSchema"
                 ],
                 :not_identifier
               )
             ) ==
               ~s[- valibot schema "log-inValibotSchema", not an identifier: rename the route, ] <>
                 "or set valibot_schema_name"
    end

    test "the raw-name rule" do
      assert NameCheck.describe(
               binding_problem(
                 [
                   kind: :rpc_function,
                   role: :execution,
                   owner: {:rpc_action, :list_1, T.Domain},
                   raw: :list_1,
                   name: "list1",
                   bare?: true
                 ],
                 :invalid_raw_name
               )
             ) ==
               "- name :list_1, a question mark or an underscore before a digit: rename the " <>
                 "rpc_action, e.g. :list1"
    end

    test "an alias problem gives its message verbatim" do
      message = ~s[The ts_alias "Geo-Point" of SomeLib.Geo is not a TypeScript identifier.]

      assert NameCheck.describe(
               problem(
                 [
                   family: :alias,
                   kind: :map_alias,
                   owner: {:type, SomeLib.Geo},
                   raw: SomeLib.Geo,
                   name: "Geo-Point",
                   source: {:ts_alias, SomeLib.Geo}
                 ],
                 {:alias, message}
               )
             ) == "- " <> message
    end
  end

  describe "the report" do
    setup do
      on_exit(fn -> :persistent_term.erase({T.CallbackScalar, :alias}) end)
    end

    defp all_families_manifest do
      InlineManifest.build!(
        domains: [T.GapDomain, T.BindingGapDomain, T.AliasDomain],
        typed_controllers: [T.BindingGapController],
        body: InlineManifest.app_custom_types(@alias_entries)
      )
      |> inject(Map.merge(@client_gaps, @binding_gaps))
    end

    test "one fixture with problems in all three families gives one message" do
      manifest = all_families_manifest()
      :persistent_term.put({T.CallbackScalar, :alias}, "Geo-Point")

      assert {:error, message} = NameCheck.check(manifest, Custom.custom_types(manifest))

      assert message == """
             Invalid generated names found.

             Client names (keys of generated objects) must be TypeScript identifiers
             ([A-Za-z_$][A-Za-z0-9_$]*). A name the formatter makes from a raw name with an underscore
             before a digit (line_1) is rejected too, since its client name (line1) doesn't tell line_1
             from line1.

               Resource #{inspect(T.GapEmb)}:
                 - field :"emb-dash" → "emb-dash" (formatted), not an identifier: add it to field_names in the resource's typescript block, e.g. "emb-dash": "embDash"

               Resource #{inspect(T.GapRes)}:
                 - argument :"arg-dash" of action :act (RPC actions act_gap) → "arg-dash" (formatted), not an identifier: add it to argument_names for the action, e.g. act: ["arg-dash": "argDash"]
                 - field :"attr-dash" → "attr-dash" (formatted), not an identifier: add it to field_names in the resource's typescript block, e.g. "attr-dash": "attrDash"
                 - argument :"calc-arg-dash" of calculation :c → "calc-arg-dash" (formatted), not an identifier: rename it, e.g. :calc_arg_dash
                 - argument :calc_arg? of calculation :c → "calcArg?" (formatted), not an identifier: rename it, e.g. :calc_arg
                 - member :u2."m2-dash" of action :act (RPC actions act_gap) → "m2-dash" (formatted), not an identifier: rename it, e.g. :m2_dash
                 - member :u2.m2_ok? of action :act (RPC actions act_gap) → "m2Ok?" (formatted), not an identifier: rename it, e.g. :m2_ok
                 - member :u."member-dash" → "member-dash" (formatted), not an identifier: rename it, e.g. :member_dash
                 - metadata :"meta-dash" of RPC action :meta_gap → "meta-dash" (formatted), not an identifier: add it to the RPC action's metadata_field_names, e.g. "meta-dash": "metaDash"

             Function, const, type and schema names must be TypeScript identifiers that aren't
             JavaScript reserved words, and a type name can't be a predefined TypeScript type name
             (string, any, …).

               RPC action :"list-todos" in #{inspect(T.BindingGapDomain)}:
                 - function "list-todos" (and 6 derived names), not an identifier: rename the rpc_action, e.g. :list_todos

               Typed query :dashboard in #{inspect(T.BindingGapDomain)}:
                 - const "dash-board" (ts_fields_const_name), not an identifier: change ts_fields_const_name
                 - result type "Dash-Result" (ts_result_type_name), not an identifier: change ts_result_type_name

               Route :login of #{inspect(T.BindingGapController)}:
                 - zod schema "login-schema" (zod_schema_name), not an identifier: change zod_schema_name

             Type aliases:

               #{inspect(T.CallbackScalar)}:
                 - The typescript_type_alias/0 result "Geo-Point" of #{inspect(T.CallbackScalar)} is not a TypeScript identifier.
             """
    end

    test "derived names of one owner are one report line" do
      manifest = all_families_manifest()

      assert {:error, message} = NameCheck.check(manifest, Custom.custom_types(manifest))
      assert message =~ ~s[- function "list-todos" (and 6 derived names), not an identifier]
      refute message =~ "validateList-todos"
    end

    test "no problems gives :ok" do
      manifest = AshTypescript.manifest()
      assert NameCheck.check(manifest, Custom.custom_types(manifest)) == :ok
    end
  end

  # ── end to end ───────────────────────────────────────────────────

  defmodule MappedRes do
    @moduledoc false
    use Ash.Resource,
      domain: AshTypescript.Manifest.NameCheckTest.MappedDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "NameCheckMappedRes"
      field_names attr_1: "attr-dash"
    end

    attributes do
      uuid_primary_key :id
      attribute :attr_1, :string, public?: true
    end

    actions do
      defaults [:read]
    end
  end

  defmodule MappedDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Manifest.NameCheckTest.MappedRes do
        rpc_action :list_mapped, :read
      end
    end

    resources do
      resource AshTypescript.Manifest.NameCheckTest.MappedRes
    end
  end

  defmodule DashMappedRes do
    @moduledoc false
    use Ash.Resource,
      domain: AshTypescript.Manifest.NameCheckTest.DashMappedDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "NameCheckDashMappedRes"
      field_names "attr-dash": "attrDash"
    end

    attributes do
      uuid_primary_key :id
      attribute :"attr-dash", :string, public?: true
    end

    actions do
      defaults [:read]
    end
  end

  defmodule DashMappedDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Manifest.NameCheckTest.DashMappedRes do
        rpc_action :list_dash_mapped, :read
      end
    end

    resources do
      resource AshTypescript.Manifest.NameCheckTest.DashMappedRes
    end
  end

  defmodule PointRes do
    @moduledoc false
    use Ash.Resource,
      domain: AshTypescript.Manifest.NameCheckTest.PointDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "NameCheckPointRes"
    end

    attributes do
      uuid_primary_key :id
      attribute :point, AshTypescript.Test.GeoPoint, public?: true
    end

    actions do
      defaults [:read]
    end
  end

  defmodule PointDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Manifest.NameCheckTest.PointRes do
        rpc_action :list_points, :read
      end
    end

    resources do
      resource AshTypescript.Manifest.NameCheckTest.PointRes
    end
  end

  defmodule CompileGapEmb do
    @moduledoc false
    use Ash.Resource, data_layer: :embedded, extensions: [AshTypescript.Resource]

    typescript do
      type_name "NameCheckCompileGapEmb"
    end

    attributes do
      attribute :"emb-dash", :string, public?: true
    end
  end

  defmodule CompileGapRes do
    @moduledoc false
    use Ash.Resource,
      domain: AshTypescript.Manifest.NameCheckTest.CompileGapDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "NameCheckCompileGapRes"
    end

    attributes do
      uuid_primary_key :id
      attribute :"attr-dash", :string, public?: true
      attribute :emb, AshTypescript.Manifest.NameCheckTest.CompileGapEmb, public?: true

      attribute :u, :union,
        public?: true,
        constraints: [types: ["member-dash": [type: :string]]]
    end

    calculations do
      calculate :c, :string, expr("x") do
        public? true
        argument :"calc-arg-dash", :string
        argument :calc_arg?, :string
      end
    end

    actions do
      defaults [:read]

      action :act, :string do
        argument :"arg-dash", :string

        argument :u2, :union,
          constraints: [types: ["m2-dash": [type: :string], m2_ok?: [type: :integer]]]

        run fn _input, _context -> {:ok, "x"} end
      end

      read :meta do
        metadata :"meta-dash", :string
      end
    end
  end

  defmodule CompileGapDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Manifest.NameCheckTest.CompileGapRes do
        rpc_action :list_compile_gap, :read
        rpc_action :act_compile_gap, :act
        rpc_action :meta_compile_gap, :meta, show_metadata: [:"meta-dash"]
      end
    end

    resources do
      resource AshTypescript.Manifest.NameCheckTest.CompileGapRes
    end
  end

  defmodule DashRpcRes do
    @moduledoc false
    use Ash.Resource,
      domain: AshTypescript.Manifest.NameCheckTest.DashRpcDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "NameCheckDashRpcRes"
    end

    attributes do
      uuid_primary_key :id
    end

    actions do
      defaults [:read]
    end
  end

  defmodule DashRpcDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Manifest.NameCheckTest.DashRpcRes do
        rpc_action :"list-todos", :read
      end
    end

    resources do
      resource AshTypescript.Manifest.NameCheckTest.DashRpcRes
    end
  end

  defmodule CompileBindingGapRes do
    @moduledoc false
    use Ash.Resource,
      domain: AshTypescript.Manifest.NameCheckTest.CompileBindingGapDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "NameCheckCompileBindingGapRes"
    end

    attributes do
      uuid_primary_key :id
    end

    actions do
      defaults [:read]
    end
  end

  defmodule CompileBindingGapDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Manifest.NameCheckTest.CompileBindingGapRes do
        typed_query :dashboard, :read do
          ts_fields_const_name "dash-board"
          ts_result_type_name "Dash-Result"
          fields [:id]
        end
      end
    end

    resources do
      resource AshTypescript.Manifest.NameCheckTest.CompileBindingGapRes
    end
  end

  defmodule CompileBindingGapController do
    @moduledoc false
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.Test.NameCheckCompileBindingGapController

      post :login do
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
        argument :code, :string
        zod_schema_name "login-schema"
      end
    end
  end

  defmodule KeywordOptionRes do
    @moduledoc false
    use Ash.Resource,
      domain: AshTypescript.Manifest.NameCheckTest.KeywordOptionDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "NameCheckKeywordOptionRes"
    end

    attributes do
      uuid_primary_key :id
    end

    actions do
      defaults [:read]
    end
  end

  defmodule KeywordOptionDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Manifest.NameCheckTest.KeywordOptionRes do
        typed_query :keyword_page, :read do
          ts_fields_const_name "default"
          ts_result_type_name "string"
          fields [:id]
        end
      end
    end

    resources do
      resource AshTypescript.Manifest.NameCheckTest.KeywordOptionRes
    end
  end

  defmodule KeywordOptionController do
    @moduledoc false
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.Test.NameCheckKeywordOptionController

      post :sign_in do
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
        argument :code, :string
        zod_schema_name "class"
        valibot_schema_name "signInValibot"
      end
    end
  end

  defmodule DashEventRes do
    @moduledoc false
    use Ash.Resource, domain: nil, notifiers: [Ash.Notifier.PubSub]

    pub_sub do
      module AshTypescript.Test.TestEndpoint
      prefix "dash_event"

      publish :create, [:id],
        event: "post-created",
        public?: true,
        returns: :map,
        constraints: [fields: [id: [type: :uuid, allow_nil?: false]]],
        transform: fn notification -> %{id: notification.data.id} end
    end

    attributes do
      uuid_primary_key :id
    end

    actions do
      defaults [:read, :create]
    end
  end

  defmodule DashEventChannel do
    @moduledoc false
    use Phoenix.Channel
    use AshTypescript.TypedChannel

    typed_channel do
      topic "dash_event:*"

      resource AshTypescript.Manifest.NameCheckTest.DashEventRes do
        publish :"post-created"
      end
    end

    def join(_topic, _payload, socket), do: {:ok, socket}
  end

  defmodule ReservedRouteController do
    @moduledoc false
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.Test.NameCheckReservedRouteController

      post :delete do
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
      end
    end
  end

  defmodule LateAliasRes do
    @moduledoc false
    use Ash.Resource,
      domain: AshTypescript.Manifest.NameCheckTest.LateAliasDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "NameCheckLateAliasRes"
    end

    attributes do
      uuid_primary_key :id
      attribute :code, AshTypescript.Manifest.NameCheckTest.AliasCode, public?: true
    end

    actions do
      defaults [:read]
    end
  end

  defmodule LateAliasDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Manifest.NameCheckTest.LateAliasRes do
        rpc_action :list_late_alias, :read
      end
    end

    resources do
      resource AshTypescript.Manifest.NameCheckTest.LateAliasRes
    end
  end

  defmodule ClassAliasTyped do
    @moduledoc false
    use Ash.TypedStruct

    def typescript_type_alias, do: "class"

    typed_struct do
      field :a, :string
    end
  end

  defmodule ClassAliasRes do
    @moduledoc false
    use Ash.Resource,
      domain: AshTypescript.Manifest.NameCheckTest.ClassAliasDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "NameCheckClassAliasRes"
    end

    attributes do
      uuid_primary_key :id
      attribute :typed, AshTypescript.Manifest.NameCheckTest.ClassAliasTyped, public?: true
    end

    actions do
      defaults [:read]
    end
  end

  defmodule ClassAliasDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Manifest.NameCheckTest.ClassAliasRes do
        rpc_action :list_class_alias, :read
      end
    end

    resources do
      resource AshTypescript.Manifest.NameCheckTest.ClassAliasRes
    end
  end

  describe "end to end" do
    test "an invalid client name fails the manifest compile with the report" do
      error =
        assert_raise RuntimeError, fn -> InlineManifest.build!(domains: [T.MappedDomain]) end

      assert error.message =~ "Invalid generated names found."

      assert error.message =~
               ~s[  Resource #{inspect(T.MappedRes)}:\n] <>
                 ~s[    - field :attr_1 → "attr-dash" (field_names), not an identifier: ] <>
                 "change the field_names value\n"
    end

    test "a field_names mapping of a non-identifier key compiles, and codegen reads its value" do
      manifest = InlineManifest.build!(domains: [T.DashMappedDomain])
      resource = Map.fetch!(AshRpc.Manifest.resource_lookup(manifest), T.DashMappedRes)

      assert ClientNames.resource_field(resource, :"attr-dash") == "attrDash"
      assert AshTypescript.VerifierChecker.check_all_verifiers([T.DashMappedRes]) == :ok
    end

    test "the probe's client gaps fail the compile" do
      error =
        assert_raise RuntimeError, fn -> InlineManifest.build!(domains: [T.CompileGapDomain]) end

      for line <- [
            ~s{- field :"emb-dash" → "emb-dash" (formatted), not an identifier: add it to field_names in the resource's typescript block, e.g. "emb-dash": "embDash"},
            ~s{- field :"attr-dash" → "attr-dash" (formatted), not an identifier: add it to field_names in the resource's typescript block, e.g. "attr-dash": "attrDash"},
            ~s{- argument :"calc-arg-dash" of calculation :c → "calc-arg-dash" (formatted), not an identifier: rename it, e.g. :calc_arg_dash},
            ~s{- argument :calc_arg? of calculation :c → "calcArg?" (formatted), not an identifier: rename it, e.g. :calc_arg},
            ~s{- argument :"arg-dash" of action :act (RPC actions act_compile_gap) → "arg-dash" (formatted), not an identifier: add it to argument_names for the action, e.g. act: ["arg-dash": "argDash"]},
            ~s{- member :u2."m2-dash" of action :act (RPC actions act_compile_gap) → "m2-dash" (formatted), not an identifier: rename it, e.g. :m2_dash},
            ~s{- member :u2.m2_ok? of action :act (RPC actions act_compile_gap) → "m2Ok?" (formatted), not an identifier: rename it, e.g. :m2_ok},
            ~s{- member :u."member-dash" → "member-dash" (formatted), not an identifier: rename it, e.g. :member_dash},
            ~s{- metadata :"meta-dash" of RPC action :meta_compile_gap → "meta-dash" (formatted), not an identifier: add it to the RPC action's metadata_field_names, e.g. "meta-dash": "metaDash"}
          ] do
        assert error.message =~ line
      end
    end

    test "a non-identifier client_name fails the compile with the report" do
      body =
        quote do
          custom_types do
            map AshTypescript.Test.GeoPoint do
              ts_alias "GeoPoint"
              field :lat, :float, allow_nil?: false, client_name: "la-t"
              field :lng, :float, allow_nil?: false
            end
          end
        end

      error =
        assert_raise RuntimeError, fn ->
          InlineManifest.build!(domains: [T.PointDomain], body: body)
        end

      assert error.message =~
               "  Type AshTypescript.Test.GeoPoint (custom_types map entry):\n" <>
                 ~s[    - field :lat → "la-t" (client_name), not an identifier: ] <>
                 "change the field's client_name in the map entry\n"
    end

    test "rpc_action :\"list-todos\" fails the compile with the report" do
      error =
        assert_raise RuntimeError, fn -> InlineManifest.build!(domains: [T.DashRpcDomain]) end

      assert error.message =~ "Invalid generated names found."

      assert error.message =~
               ~s[  RPC action :"list-todos" in #{inspect(T.DashRpcDomain)}:\n] <>
                 ~s[    - function "list-todos" (and 6 derived names), not an identifier: ] <>
                 "rename the rpc_action, e.g. :list_todos\n"
    end

    test "the probe's binding gaps fail the compile" do
      error =
        assert_raise RuntimeError, fn ->
          InlineManifest.build!(
            domains: [T.CompileBindingGapDomain],
            typed_controllers: [T.CompileBindingGapController]
          )
        end

      assert error.message =~
               ~s[  Typed query :dashboard in #{inspect(T.CompileBindingGapDomain)}:\n] <>
                 ~s[    - const "dash-board" (ts_fields_const_name), not an identifier: ] <>
                 "change ts_fields_const_name\n" <>
                 ~s[    - result type "Dash-Result" (ts_result_type_name), not an identifier: ] <>
                 "change ts_result_type_name\n"

      assert error.message =~
               ~s[  Route :login of #{inspect(T.CompileBindingGapController)}:\n] <>
                 ~s[    - zod schema "login-schema" (zod_schema_name), not an identifier: ] <>
                 "change zod_schema_name\n"
    end

    test "a reserved word or a type keyword as an option value fails the compile, naming the option" do
      error =
        assert_raise RuntimeError, fn ->
          InlineManifest.build!(
            domains: [T.KeywordOptionDomain],
            typed_controllers: [T.KeywordOptionController]
          )
        end

      assert error.message =~
               ~s[  Typed query :keyword_page in #{inspect(T.KeywordOptionDomain)}:\n] <>
                 ~s[    - const "default" (ts_fields_const_name), a JavaScript reserved word: ] <>
                 "change ts_fields_const_name\n" <>
                 ~s[    - result type "string" (ts_result_type_name), a predefined TypeScript ] <>
                 "type name: change ts_result_type_name\n"

      assert error.message =~
               ~s[  Route :sign_in of #{inspect(T.KeywordOptionController)}:\n] <>
                 ~s[    - zod schema "class" (zod_schema_name), a JavaScript reserved word: ] <>
                 "change zod_schema_name\n"
    end

    test "a typed channel event that isn't an identifier fails the compile with the report" do
      error =
        assert_raise RuntimeError, fn ->
          InlineManifest.build!(typed_channels: [T.DashEventChannel])
        end

      assert error.message =~
               ~s[  Publication "post-created" of #{inspect(T.DashEventChannel)}:\n] <>
                 ~s[    - event "post-created" (and 1 derived names), not an identifier: ] <>
                 "rename the event, e.g. :post_created\n"
    end

    test "a reserved route name fails the compile with the report" do
      error =
        assert_raise RuntimeError, fn ->
          InlineManifest.build!(typed_controllers: [T.ReservedRouteController])
        end

      assert error.message =~ "Invalid generated names found."

      assert error.message =~
               ~s[  Route :delete of #{inspect(T.ReservedRouteController)}:\n] <>
                 ~s[    - function "delete", a JavaScript reserved word: rename the route, ] <>
                 "for example :delete_item\n"
    end

    test "a reached scalar ts_alias \"Custom-Id\" fails the compile with the report" do
      body =
        InlineManifest.app_custom_types([
          quote do
            scalar AshTypescript.Manifest.NameCheckTest.AliasCode, :string do
              ts_alias "Custom-Id"
            end
          end
        ])

      error =
        assert_raise RuntimeError, fn ->
          InlineManifest.build!(domains: [T.LateAliasDomain], body: body)
        end

      assert error.message =~ "Invalid generated names found."

      assert error.message =~
               "Type aliases:\n\n" <>
                 "  #{inspect(T.AliasCode)}:\n" <>
                 ~s[    - The ts_alias "Custom-Id" of #{inspect(T.AliasCode)} is not a TypeScript identifier.]
    end

    test "a reached ts_alias \"Geo-Point\" fails the compile with the report" do
      body =
        quote do
          custom_types do
            map AshTypescript.Test.GeoPoint do
              ts_alias "Geo-Point"
              field :lat, :float, allow_nil?: false
              field :lng, :float, allow_nil?: false
            end
          end
        end

      error =
        assert_raise RuntimeError, fn ->
          InlineManifest.build!(domains: [T.PointDomain], body: body)
        end

      assert error.message =~ "Invalid generated names found."

      assert error.message =~
               "Type aliases:\n\n" <>
                 "  AshTypescript.Test.GeoPoint:\n" <>
                 ~s[    - The ts_alias "Geo-Point" of AshTypescript.Test.GeoPoint is not a TypeScript identifier.]
    end

    test "a bad typescript_type_alias/0 string fails the compile with the report, not an ArgumentError" do
      error =
        assert_raise RuntimeError, fn -> InlineManifest.build!(domains: [T.ClassAliasDomain]) end

      assert error.message =~ "Invalid generated names found."

      assert error.message =~
               "  #{inspect(T.ClassAliasTyped)}:\n" <>
                 ~s[    - The typescript_type_alias/0 result "class" of #{inspect(T.ClassAliasTyped)} ] <>
                 "is a TypeScript reserved word."
    end

    test "an unreached entry's bad ts_alias builds" do
      # decision unreached-names A, end to end
      body =
        InlineManifest.app_custom_types([
          quote do
            map SomeLib.Coordinates do
              ts_alias "Geo-Coordinates"
              field :lat, :float
            end
          end
        ])

      manifest =
        InlineManifest.build!(domains: [AshTypescript.Test.SecondDomain], body: body)

      assert %Ash.Info.Manifest{} = manifest

      assert Custom.custom_types(manifest).declared[SomeLib.Coordinates].ts_alias ==
               "Geo-Coordinates"
    end
  end
end
