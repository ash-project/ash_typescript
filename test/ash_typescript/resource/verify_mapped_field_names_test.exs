# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Resource.VerifyMappedFieldNamesTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias AshTypescript.VerifierChecker

  test "a mapping of a name with a ? or an underscore before a digit passes" do
    defmodule MappedRes do
      use Ash.Resource,
        domain: nil,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshTypescript.Resource]

      typescript do
        type_name "VerifyMappedFieldNamesMappedRes"
        field_names is_done?: "isDone", line_1: "lineOne"
      end

      attributes do
        uuid_primary_key :id
        attribute :is_done?, :boolean, public?: true
        attribute :line_1, :string, public?: true
      end
    end

    assert :ok = VerifierChecker.check_all_verifiers([MappedRes])
  end

  test "a mapping of a name that isn't an identifier passes" do
    defmodule DashRes do
      use Ash.Resource,
        domain: nil,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshTypescript.Resource]

      typescript do
        type_name "VerifyMappedFieldNamesDashRes"
        field_names "attr-dash": "attrDash"
      end

      attributes do
        uuid_primary_key :id
        attribute :"attr-dash", :string, public?: true
      end
    end

    assert :ok = VerifierChecker.check_all_verifiers([DashRes])
  end

  test "a key that needs no mapping is rejected" do
    capture_io(:stderr, fn ->
      defmodule KeyRes do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "VerifyMappedFieldNamesKeyRes"
          field_names [{:"attr-dash", "attrDash"}, {:title, "heading"}]
        end

        attributes do
          uuid_primary_key :id
          attribute :"attr-dash", :string, public?: true
          attribute :title, :string, public?: true
        end
      end
    end)

    assert {:error, message} = VerifierChecker.check_all_verifiers([__MODULE__.KeyRes])
    assert message =~ "Invalid field_names configuration found"
    assert message =~ "- Field title is already a valid name and doesn't need mapping"
    refute message =~ "attr-dash"
  end

  test "a value that isn't a string is rejected" do
    capture_io(:stderr, fn ->
      defmodule ValueRes do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "VerifyMappedFieldNamesValueRes"
          field_names is_done?: :isDone
        end

        attributes do
          uuid_primary_key :id
          attribute :is_done?, :boolean, public?: true
        end
      end
    end)

    assert {:error, message} = VerifierChecker.check_all_verifiers([__MODULE__.ValueRes])
    assert message =~ "Replacement name :isDone must be a string"
  end

  test "a mapping of an aggregate's name passes" do
    defmodule AggregateRes do
      use Ash.Resource,
        domain: nil,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshTypescript.Resource]

      typescript do
        type_name "VerifyMappedFieldNamesAggregateRes"
        field_names children_1: "childrenOne"
      end

      attributes do
        uuid_primary_key :id
        attribute :parent_id, :uuid, public?: true
      end

      relationships do
        has_many :children, __MODULE__, destination_attribute: :parent_id, public?: true
      end

      aggregates do
        count :children_1, :children, public?: true
      end
    end

    assert :ok = VerifierChecker.check_all_verifiers([AggregateRes])
  end

  test "a key that is no field of the resource is rejected" do
    capture_io(:stderr, fn ->
      defmodule MissingRes do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "VerifyMappedFieldNamesMissingRes"
          field_names line_1: "lineOne"
        end

        attributes do
          uuid_primary_key :id
        end
      end
    end)

    assert {:error, message} = VerifierChecker.check_all_verifiers([__MODULE__.MissingRes])

    assert message =~
             "- Field line_1 does not exist on resource #{inspect(__MODULE__.MissingRes)}"
  end
end
