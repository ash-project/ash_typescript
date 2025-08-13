defmodule AshTypescript.Rpc.RequestedFieldsProcessorUnionTypesTest do
  use ExUnit.Case
  alias AshTypescript.Rpc.RequestedFieldsProcessor

  describe "content union type - embedded resource members" do
    test "processes TextContent union member with field selection" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          %{
            content: [
              %{
                text: [:id, :text, :formatting, :word_count]
              }
            ]
          }
        ])

      assert select == [:id, :title, :content]
      assert load == []

      assert extraction_template == [
               :id,
               :title,
               content: [text: [:id, :text, :formatting, :word_count]]
             ]
    end

    test "processes ChecklistContent union member with field selection" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            content: [
              %{
                checklist: [:id, :title, :items, :allow_reordering]
              }
            ]
          }
        ])

      assert select == [:id, :content]
      assert load == []

      assert extraction_template == [
               :id,
               content: [checklist: [:id, :title, :items, :allow_reordering]]
             ]
    end

    test "processes LinkContent union member with field selection and calculations" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            content: [
              %{
                link: [
                  :id,
                  :url,
                  :title,
                  :description,
                  :is_external,
                  :display_title,
                  :domain
                ]
              }
            ]
          }
        ])

      assert select == [:id, :content]

      assert load == [
               {:content, [{:link, [:display_title, :domain]}]}
             ]

      assert extraction_template == [
               :id,
               content: [
                 link: [:id, :url, :title, :description, :is_external, :display_title, :domain]
               ]
             ]
    end

    test "processes multiple embedded resource union members in single map" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            content: [
              %{
                text: [:id, :text, :formatting],
                checklist: [:id, :title, :items],
                link: [:id, :url, :title]
              }
            ]
          }
        ])

      assert select == [:id, :content]

      assert load == []

      # The order of fields in maps isn't guaranteed, so we need to check
      # that all the expected fields are present regardless of order
      assert [:id | rest] = extraction_template
      assert [{:content, content_fields}] = rest

      # Sort the content fields to compare them
      sorted_content_fields = Enum.sort(content_fields)

      expected_sorted =
        Enum.sort([
          {:text, [:id, :text, :formatting]},
          {:checklist, [:id, :title, :items]},
          {:link, [:id, :url, :title]}
        ])

      assert sorted_content_fields == expected_sorted
    end

    test "processes multiple embedded resource union members in separate maps" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            content: [
              %{text: [:id, :text, :formatting]},
              %{link: [:id, :url, :title]},
              %{checklist: [:id, :title, :items]}
            ]
          }
        ])

      assert select == [:id, :content]

      assert load == []

      assert extraction_template == [
               :id,
               content: [
                 text: [:id, :text, :formatting],
                 link: [:id, :url, :title],
                 checklist: [:id, :title, :items]
               ]
             ]
    end
  end

  describe "content union type - simple members" do
    test "processes note (string) union member" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          %{
            content: [
              :note
            ]
          }
        ])

      assert select == [:id, :title, :content]
      assert load == []
      assert extraction_template == [:id, :title, content: [:note]]
    end

    test "processes priority_value (integer) union member" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            content: [
              :priority_value
            ]
          }
        ])

      assert select == [:id, :content]
      assert load == []
      assert extraction_template == [:id, content: [:priority_value]]
    end

    test "processes mixed simple and embedded resource union members" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            content: [
              :note,
              :priority_value,
              %{
                text: [:id, :text, :formatting]
              }
            ]
          }
        ])

      assert select == [:id, :content]
      assert load == []

      assert extraction_template == [
               :id,
               content: [
                 :note,
                 :priority_value,
                 text: [:id, :text, :formatting]
               ]
             ]
    end

    test "processes mixed simple and complex union members in single map" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            content: [
              :note,
              %{
                text: [:id, :text, :formatting, :display_text],
                checklist: [:id, :title, :total_items]
              }
            ]
          }
        ])

      assert select == [:id, :content]
      assert load == [{:content, [{:text, [:display_text]}, {:checklist, [:total_items]}]}]

      # Check extraction template, handling potential ordering issues
      assert [:id | rest] = extraction_template
      assert [{:content, content_fields}] = rest

      # Simple members should be first, then complex members
      assert :note in content_fields

      # Find the complex members
      text_entry =
        Enum.find(content_fields, fn
          {:text, _} -> true
          _ -> false
        end)

      checklist_entry =
        Enum.find(content_fields, fn
          {:checklist, _} -> true
          _ -> false
        end)

      assert text_entry == {:text, [:id, :text, :formatting, :display_text]}
      assert checklist_entry == {:checklist, [:id, :title, :total_items]}
    end
  end

  describe "attachments array union type" do
    test "processes file attachment union member with field selection" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            attachments: [
              %{
                file: [:filename, :size, :mime_type]
              }
            ]
          }
        ])

      assert select == [:id, :attachments]
      assert load == []
      assert extraction_template == [:id, attachments: [file: [:filename, :size, :mime_type]]]
    end

    test "processes image attachment union member with field selection" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            attachments: [
              %{
                image: [:filename, :width, :height, :alt_text]
              }
            ]
          }
        ])

      assert select == [:id, :attachments]
      assert load == []

      assert extraction_template == [
               :id,
               attachments: [image: [:filename, :width, :height, :alt_text]]
             ]
    end

    test "processes url attachment union member (simple type)" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            attachments: [
              :url
            ]
          }
        ])

      assert select == [:id, :attachments]
      assert load == []
      assert extraction_template == [:id, attachments: [:url]]
    end

    test "processes mixed attachment union members in separate maps" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            attachments: [
              %{
                file: [:filename, :size, :mime_type]
              },
              %{
                image: [:filename, :width, :height]
              },
              :url
            ]
          }
        ])

      assert select == [:id, :attachments]

      assert load == []

      # Check extraction template, handling ordering
      assert [:id | rest] = extraction_template
      assert [{:attachments, attachment_fields}] = rest

      # Check all expected fields are present
      assert :url in attachment_fields
      assert {:file, [:filename, :size, :mime_type]} in attachment_fields
      assert {:image, [:filename, :width, :height]} in attachment_fields
    end

    test "processes mixed attachment union members in single map" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            attachments: [
              :url,
              %{
                file: [:filename, :size, :mime_type],
                image: [:filename, :width, :height]
              }
            ]
          }
        ])

      assert select == [:id, :attachments]

      assert load == []

      # Check extraction template, handling ordering
      assert [:id | rest] = extraction_template
      assert [{:attachments, attachment_fields}] = rest

      # Check all expected fields are present
      assert :url in attachment_fields
      assert {:file, [:filename, :size, :mime_type]} in attachment_fields
      assert {:image, [:filename, :width, :height]} in attachment_fields
    end
  end

  describe "status_info union type - map_with_tag storage" do
    test "processes simple status_info union member" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            status_info: [
              :simple
            ]
          }
        ])

      assert select == [:id, :status_info]
      assert load == []
      assert extraction_template == [:id, status_info: [:simple]]
    end

    test "processes detailed status_info union member" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            status_info: [
              :detailed
            ]
          }
        ])

      assert select == [:id, :status_info]
      assert load == []
      assert extraction_template == [:id, status_info: [:detailed]]
    end

    test "processes automated status_info union member" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            status_info: [
              :automated
            ]
          }
        ])

      assert select == [:id, :status_info]
      assert load == []
      assert extraction_template == [:id, status_info: [:automated]]
    end

    test "processes multiple status_info union members" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            status_info: [
              :simple,
              :detailed,
              :automated
            ]
          }
        ])

      assert select == [:id, :status_info]
      assert load == []
      assert extraction_template == [:id, status_info: [:simple, :detailed, :automated]]
    end
  end

  describe "mixed union types with other field types" do
    test "processes union types with attributes and relationships" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          :completed,
          %{user: [:id, :name]},
          %{
            content: [
              :note,
              %{
                text: [:id, :text, :formatting]
              }
            ]
          },
          %{
            attachments: [
              %{
                file: [:filename, :size]
              },
              :url
            ]
          }
        ])

      assert select == [:id, :title, :completed, :content, :attachments]

      assert load == [
               {:user, [:id, :name]}
             ]

      assert extraction_template == [
               :id,
               :title,
               :completed,
               user: [:id, :name],
               content: [
                 :note,
                 text: [:id, :text, :formatting]
               ],
               attachments: [
                 :url,
                 file: [:filename, :size]
               ]
             ]
    end

    test "processes union types with calculations and aggregates" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :is_overdue,
          :comment_count,
          %{
            content: [
              %{
                text: [:id, :text, :word_count]
              }
            ]
          },
          %{
            status_info: [
              :detailed
            ]
          }
        ])

      assert select == [:id, :content, :status_info]

      assert load == [
               :is_overdue,
               :comment_count
             ]

      assert extraction_template == [
               :id,
               :is_overdue,
               :comment_count,
               content: [text: [:id, :text, :word_count]],
               status_info: [:detailed]
             ]
    end

    test "processes all union types together" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            content: [
              :note,
              %{
                text: [:id, :text]
              }
            ]
          },
          %{
            attachments: [
              %{
                file: [:filename, :size]
              },
              %{
                image: [:filename, :width]
              }
            ]
          },
          %{
            status_info: [
              :simple,
              :detailed
            ]
          }
        ])

      assert select == [:id, :content, :attachments, :status_info]

      assert load == []

      assert extraction_template == [
               :id,
               content: [
                 :note,
                 text: [:id, :text]
               ],
               attachments: [
                 file: [:filename, :size],
                 image: [:filename, :width]
               ],
               status_info: [:simple, :detailed]
             ]
    end
  end

  describe "union type validation and error handling" do
    test "rejects invalid union member" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            content: [
              :invalid_member
            ]
          }
        ])

      assert error ==
               {:unknown_field, :invalid_member, "union_attribute", "content.invalidMember"}
    end

    test "rejects invalid field in embedded resource union member" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            content: [
              %{
                text: [:id, :invalid_field]
              }
            ]
          }
        ])

      assert error ==
               {:unknown_field, :invalid_field, AshTypescript.Test.TodoContent.TextContent,
                "content.text.invalidField"}
    end

    test "rejects invalid field in map union member with field constraints" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            attachments: [
              %{
                file: [:filename, :invalid_field]
              }
            ]
          }
        ])

      assert error == {:unknown_field, :invalid_field, "map", "attachments.file.invalidField"}
    end

    test "rejects invalid union member in attachments array" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            attachments: [
              :invalid_attachment_type
            ]
          }
        ])

      assert error ==
               {:unknown_field, :invalid_attachment_type, "union_attribute",
                "attachments.invalidAttachmentType"}
    end

    test "rejects invalid union member in status_info" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            status_info: [
              :invalid_status
            ]
          }
        ])

      assert error ==
               {:unknown_field, :invalid_status, "union_attribute", "statusInfo.invalidStatus"}
    end

    test "rejects empty union field selection" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            content: []
          }
        ])

      assert error == {:requires_field_selection, :union, "content"}
    end

    test "rejects union attribute requested as simple atom" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :content
        ])

      assert error == {:requires_field_selection, :union_attribute, "content"}
    end

    test "rejects file attachment requested as simple atom (requires field selection)" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            attachments: [
              :file
            ]
          }
        ])

      assert error == {:requires_field_selection, :complex_type, "attachments.file"}
    end

    test "rejects image attachment requested as simple atom (requires field selection)" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            attachments: [
              :image
            ]
          }
        ])

      assert error == {:requires_field_selection, :complex_type, "attachments.image"}
    end

    test "rejects duplicate union field requests" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            content: [
              :note,
              :note
            ]
          }
        ])

      assert error == {:duplicate_field, :note, "content.note"}
    end

    test "accepts union members in single map with different members" do
      # This test verifies that we can specify multiple different union members
      # in a single map, which is the feature we just added
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            content: [
              %{
                text: [:id, :text],
                checklist: [:id, :title]
              }
            ]
          }
        ])

      assert select == [:content]
      assert load == []

      # Check extraction template, handling ordering
      assert [{:content, content_fields}] = extraction_template

      # Sort to compare
      sorted_fields = Enum.sort(content_fields)

      expected_sorted =
        Enum.sort([
          {:text, [:id, :text]},
          {:checklist, [:id, :title]}
        ])

      assert sorted_fields == expected_sorted
    end

    test "rejects duplicate union members across different formats" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            content: [
              %{text: [:id, :text]},
              %{text: [:id, :text, :formatting]}
            ]
          }
        ])

      assert error == {:duplicate_field, :text, "content.text"}
    end

    test "rejects mixed simple and nested selection for same union member" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            content: [
              :note,
              %{
                note: [:invalid]
              }
            ]
          }
        ])

      assert error == {:duplicate_field, :note, "content.note"}
    end
  end

  describe "complex union field selection scenarios" do
    test "processes nested calculations within embedded resource union members" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            content: [
              %{
                text: [
                  :id,
                  :text,
                  :formatting,
                  :display_text,
                  :is_formatted
                ]
              }
            ]
          }
        ])

      assert select == [:id, :content]

      assert load == [
               {:content, [{:text, [:display_text, :is_formatted]}]}
             ]

      assert extraction_template == [
               :id,
               content: [text: [:id, :text, :formatting, :display_text, :is_formatted]]
             ]
    end

    test "processes union field selection with deep nesting" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            content: [
              %{
                checklist: [
                  :id,
                  :title,
                  :items,
                  :total_items,
                  :completed_count,
                  :progress_percentage
                ]
              }
            ]
          }
        ])

      assert select == [:id, :content]

      assert load == [
               {:content,
                [
                  {:checklist, [:total_items, :completed_count, :progress_percentage]}
                ]}
             ]

      assert extraction_template == [
               :id,
               content: [
                 checklist: [
                   :id,
                   :title,
                   :items,
                   :total_items,
                   :completed_count,
                   :progress_percentage
                 ]
               ]
             ]
    end

    test "handles union members with no field selection needed (simple types only)" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            content: [
              :note,
              :priority_value
            ]
          },
          %{
            attachments: [
              # Only URL since file/image require field selection
              :url
            ]
          },
          %{
            status_info: [
              :simple,
              :detailed,
              :automated
            ]
          }
        ])

      assert select == [:id, :content, :attachments, :status_info]
      assert load == []

      assert extraction_template == [
               :id,
               content: [:note, :priority_value],
               attachments: [:url],
               status_info: [:simple, :detailed, :automated]
             ]
    end
  end

  describe "union type edge cases" do
    test "handles single union member selection" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            content: [
              %{
                text: [:id, :text]
              }
            ]
          }
        ])

      assert select == [:id, :content]
      assert load == []
      assert extraction_template == [:id, content: [text: [:id, :text]]]
    end

    test "handles union member with minimal field selection" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            content: [
              %{
                text: [:id]
              }
            ]
          }
        ])

      assert select == [:id, :content]
      assert load == []
      assert extraction_template == [:id, content: [text: [:id]]]
    end

    test "processes union attribute with only simple members" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            content: [
              :note,
              :priority_value
            ]
          }
        ])

      assert select == [:id, :content]
      assert load == []
      assert extraction_template == [:id, content: [:note, :priority_value]]
    end

    test "processes map union member with field selection" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            attachments: [
              %{
                file: [:filename, :size, :mime_type]
              }
            ]
          }
        ])

      assert select == [:id, :attachments]
      assert load == []
      assert extraction_template == [:id, attachments: [file: [:filename, :size, :mime_type]]]
    end
  end
end
