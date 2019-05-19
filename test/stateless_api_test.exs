defmodule StatelessApiTest do
  use ExUnit.Case
  import Tesla.Mock
  import SlackDB

  @s_url "https://slack.com/api"

  setup do
    mock(fn
      %{
        method: :post,
        url: "#{@s_url}/search.messages",
        body: "highlight=false&query=in%3A%23general+%22key%22&sort=timestamp&sort_dir=desc"
      } ->
        %Tesla.Env{
          status: 200,
          body:
            "{\"messages\":{\"matches\":[{\"channel\":{\"id\":\"CFFD4EEMR\",\"name\":\"general\"},\"text\":\"key :monkey:\",\"ts\":\"1555913457.017900\"}],\"total\":1},\"ok\":true,\"query\":\"in:#general \\\"key\\\"\"}"
        }

      %{
        method: :post,
        url: "#{@s_url}/search.messages",
        body:
          "highlight=false&query=in%3A%23general+from%3AJeanie+%22key%22&sort=timestamp&sort_dir=desc"
      } ->
        %Tesla.Env{
          status: 200,
          body:
            "{\"messages\":{\"matches\":[{\"channel\":{\"id\":\"CFFD4EEMR\",\"name\":\"general\"},\"text\":\"key :monkey:\",\"ts\":\"1555913457.017900\"}],\"total\":1},\"ok\":true,\"query\":\"in:#general \\\"key\\\"\"}"
        }

      # %{
      #   method: :post,
      #   url: "#{@s_url}/reactions.get",
      #   body: ""
      # } ->
      #   %Tesla.Env{
      #     status: 200,
      #     body:
      #       "{\"message\":{\"reactions\":[{\"count\":1},{\"count\":3},{\"count\":1}]},\"ok\":true}"
      #   }

      %{
        method: :post,
        url: "#{@s_url}/conversations.replies",
        # limit value in the body is spoofed. the actual response is from when limit=3
        body: "channel=CFFD4EEMR&cursor=&limit=200&ts=1555913457.017900"
      } ->
        %Tesla.Env{
          status: 200,
          body:
            "{\"has_more\":true,\"messages\":[{\"key_at_top_of_thread\":\"fake\"},{\"text\":\"3\",\"ts\":\"1555913464.018400\"},{\"reactions\":[{\"count\":1,\"name\":\"four\",\"users\":[\"UFAM5HN5R\"]},{\"count\":1,\"name\":\"1234\",\"users\":[\"UFAM5HN5R\"]},{\"count\":1,\"name\":\"clock4\",\"users\":[\"UFAM5HN5R\"]}],\"text\":\"4\",\"ts\":\"1555913465.018600\"},{\"text\":\"5\",\"ts\":\"1555913465.018800\"}],\"ok\":true,\"response_metadata\":{\"next_cursor\":\"bmV4dF90czoxNTU1OTEzNDY0MDE4MjAw\"}}"
        }

      %{
        method: :post,
        url: "#{@s_url}/conversations.replies",
        # limit value in the body is spoofed. the actual response is from when limit=3
        body:
          "channel=CFFD4EEMR&cursor=bmV4dF90czoxNTU1OTEzNDY0MDE4MjAw&limit=200&ts=1555913457.017900"
      } ->
        %Tesla.Env{
          status: 200,
          body:
            "{\"has_more\":false,\"messages\":[{\"key_at_top_of_thread\":\"fake\"},{\"text\":\"1\",\"ts\":\"1555913463.018000\"},{\"client_msg_id\":\"b8e55066-bb85-4734-bdae-d3f2ab8f4dd7\",\"parent_user_id\":\"UFAM5HN5R\",\"reactions\":[{\"count\":4}],\"text\":\"2\",\"ts\":\"1555913464.018200\"}],\"ok\":true}"
        }

      %{
        method: :post,
        url: "#{@s_url}/conversations.replies",
        body: "channel=CFFD4EEMR&cursor=&limit=1&ts=1555913457.017900"
      } ->
        %Tesla.Env{
          status: 200,
          body:
            "{\"has_more\":true,\"messages\":[{\"key_at_top_of_thread\":\"fake\"},{\"text\":\"5\",\"ts\":\"1555913465.018800\"}],\"ok\":true,\"response_metadata\":{\"next_cursor\":\"bmV4dF90czoxNTU1OTEzNDY0MDE4MjAw\"}}"
        }

      %{
        method: :post,
        url: "#{@s_url}/chat.postMessage"
      } ->
        %Tesla.Env{
          status: 200,
          body:
            "{\"channel\":\"CHU427918\",\"message\":{\"text\":\"value\",\"thread_ts\":\"1556164115.000100\",\"ts\":\"1556164115.000200\"},\"ok\":true,\"ts\":\"1556164115.000200\"}"
        }

      %{
        method: :post,
        url: "#{@s_url}/conversations.invite"
      } ->
        %Tesla.Env{
          status: 200,
          body: "{\"channel\":{\"id\":\"C012AB3CD\",\"name\":\"general\"},\"ok\":true}"
        }
    end)

    :ok
  end

  test "search" do
    ans =
      {:ok,
       %SlackDB.Key{
         channel_id: "CFFD4EEMR",
         channel_name: "general",
         key_phrase: "key",
         metadata: [:single_back],
         server_name: "server",
         ts: "1555913457.017900"
       }}

    assert SlackDB.Utils.search("server", "general", "key", false) === ans
    assert SlackDB.Utils.search("server", "general", "key", true) === ans
  end

  test "votable key" do
    assert SlackDB.Key.get_value(%SlackDB.Key{
             channel_id: "CFFD4EEMR",
             channel_name: "general",
             key_phrase: "key",
             metadata: [:voting],
             server_name: "server",
             ts: "1555913457.017900"
           }) === {:ok, "2"}
  end

  test "multiple key" do
    assert SlackDB.Key.get_value(%SlackDB.Key{
             channel_id: "CFFD4EEMR",
             channel_name: "general",
             key_phrase: "key",
             metadata: [:multiple],
             server_name: "server",
             ts: "1555913457.017900"
           }) === {:ok, ["1", "2", "3", "4", "5"]}
  end

  test "single front key" do
    assert SlackDB.Key.get_value(%SlackDB.Key{
             channel_id: "CFFD4EEMR",
             channel_name: "general",
             key_phrase: "key",
             metadata: [:single_front],
             server_name: "server",
             ts: "1555913457.017900"
           }) === {:ok, "1"}
  end

  test "single back key" do
    assert SlackDB.Key.get_value(%SlackDB.Key{
             channel_id: "CFFD4EEMR",
             channel_name: "general",
             key_phrase: "key",
             metadata: [:single_back],
             server_name: "server",
             ts: "1555913457.017900"
           }) === {:ok, "5"}
  end

  test "read" do
    assert read!("server", "general", "key") == "5"
    assert read("server", "general", "key") == {:ok, "5"}

    assert read("not_in_config", "general", "key") == {:error, "server_not_found_in_config"}
  end

  test "post_thread and append" do
    ans = [
      ok: %{
        "channel" => "CHU427918",
        "message" => %{
          "text" => "value",
          "thread_ts" => "1556164115.000100",
          "ts" => "1556164115.000200"
        },
        "ok" => true,
        "ts" => "1556164115.000200"
      }
    ]

    assert SlackDB.Utils.post_thread("xoxb", "channel_id", "value", "thread_ts") === ans
    assert append("server", "general", "key", "value") === ans
  end

  test "invite_supervisor" do
    assert invite_supervisors("server", "user_id") ===
             {:ok, %{"id" => "C012AB3CD", "name" => "general"}}
  end
end
