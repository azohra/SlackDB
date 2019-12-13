defmodule SlackDB.SearchTest do
  use ExUnit.Case

  import Mox
  import SlackDB.Search

  @pagination_result_1 %{
    "matches" => [
      %{
        "channel" => %{
          "id" => "CQGTEPMUL",
          "name" => "new"
        },
        "text" => "key again",
        "ts" => "1575909803.000800"
      },
      %{
        "channel" => %{
          "id" => "CQGTEPMUL",
          "name" => "new"
        },
        "text" => "haha key :family:",
        "ts" => "1575908537.000600"
      }
    ],
    "pagination" => %{
      "page" => 1,
      "page_count" => 2
    }
  }

  @pagination_result_2 %{
    "matches" => [
      %{
        "channel" => %{
          "id" => "CQGTEPMUL",
          "name" => "new"
        },
        "text" => "key hello one two three four five six",
        "ts" => "1575909803.000800"
      },
      %{
        "channel" => %{
          "id" => "CQGTEPMUL",
          "name" => "new"
        },
        "text" => "key :family:  :anchor: :unkown:",
        "ts" => "1575908537.000600"
      }
    ],
    "pagination" => %{
      "page" => 2,
      "page_count" => 2
    }
  }

  setup do
    Client.Mock
    |> expect(:search_messages, 6, fn
      _, _, [page: 1] -> {:ok, @pagination_result_1}
      _, _, [page: 2] -> {:ok, @pagination_result_2}
    end)

    :ok
  end

  test "search error catching" do
    assert search("not_found", "channel", "key") ==
             {:error, "KeyError: couldn't find key `not_found`"}

    assert search("improperly_configed", "channel", "key") ==
             {:error, "KeyError: couldn't find key `bot_name`"}
  end

  test "search pagination" do
    key_ans = %SlackDB.Key{
      channel_id: "CQGTEPMUL",
      channel_name: "new",
      key_phrase: "key",
      metadata: [:multiple, :undeletable, :unknown_emoji],
      server_name: "server",
      ts: "1575908537.000600"
    }

    assert search("server", "channel", "key") == {:ok, key_ans}
    assert search("server", "channel", "key", false) == {:ok, key_ans}

    # white space sensitive
    assert search("server", "channel", "key ") == {:error, "found_no_matches"}
  end

  # test "search" do
  #   ans =
  #     {:ok,
  #      %SlackDB.Key{
  #        channel_id: "CFFD4EEMR",
  #        channel_name: "general",
  #        key_phrase: "key",
  #        metadata: [:single_back],
  #        server_name: "test",
  #        ts: "1555913457.017900"
  #      }}

  #   assert SlackDB.Search.search("server", "general", "key", false) === ans
  #   assert SlackDB.Search.search("server", "general", "key", true) === ans
  # end

  # test "votable key" do
  #   assert SlackDB.Key.get_value(%SlackDB.Key{
  #            channel_id: "CFFD4EEMR",
  #            channel_name: "general",
  #            key_phrase: "key",
  #            metadata: [:voting],
  #            server_name: "server",
  #            ts: "1555913457.017900"
  #          }) === {:ok, "2"}
  # end

  # test "multiple key" do
  #   assert SlackDB.Key.get_value(%SlackDB.Key{
  #            channel_id: "CFFD4EEMR",
  #            channel_name: "general",
  #            key_phrase: "key",
  #            metadata: [:multiple],
  #            server_name: "server",
  #            ts: "1555913457.017900"
  #          }) === {:ok, ["1", "2", "3", "4", "5"]}
  # end

  # test "single front key" do
  #   assert SlackDB.Key.get_value(%SlackDB.Key{
  #            channel_id: "CFFD4EEMR",
  #            channel_name: "general",
  #            key_phrase: "key",
  #            metadata: [:single_front],
  #            server_name: "server",
  #            ts: "1555913457.017900"
  #          }) === {:ok, "1"}
  # end

  # test "single back key" do
  #   assert SlackDB.Key.get_value(%SlackDB.Key{
  #            channel_id: "CFFD4EEMR",
  #            channel_name: "general",
  #            key_phrase: "key",
  #            metadata: [:single_back],
  #            server_name: "server",
  #            ts: "1555913457.017900"
  #          }) === {:ok, "5"}
  # end

  # test "read" do
  #   assert read!("server", "general", "key") == "5"
  #   assert read("server", "general", "key") == {:ok, "5"}

  #   assert read("not_in_config", "general", "key") == {:error, "server_not_found_in_config"}
  # end

  # test "post_thread and append" do
  #   ans = [
  #     ok: %{
  #       "channel" => "CHU427918",
  #       "message" => %{
  #         "text" => "value",
  #         "thread_ts" => "1556164115.000100",
  #         "ts" => "1556164115.000200"
  #       },
  #       "ok" => true,
  #       "ts" => "1556164115.000200"
  #     }
  #   ]

  #   assert SlackDB.Messages.post_thread("xoxb", "channel_id", "value", "thread_ts") === ans
  #   assert append("server", "general", "key", "value") === ans
  # end

  # test "invite_supervisor" do
  #   assert invite_supervisors("server", "user_id") ===
  #            {:ok, %{"id" => "C012AB3CD", "name" => "general"}}
  # end
end
