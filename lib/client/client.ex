defmodule SlackDB.Client do
  @moduledoc false

  use Tesla

  require Logger

  @callback search_messages(String.t(), String.t()) ::
              {:error, any()} | {:ok, map()}
  @callback chat_postMessage(String.t(), String.t(), String.t(), String.t() | atom()) ::
              {:error, any()} | {:ok, map()}
  @callback chat_delete(String.t(), String.t(), String.t()) ::
              {:error, any()} | {:ok, map()}
  @callback conversations_create(String.t(), String.t(), boolean()) ::
              {:error, any()} | {:ok, map()}
  @callback conversations_archive(String.t(), String.t()) ::
              {:error, any()} | {:ok, map()}
  @callback conversations_invite(String.t(), String.t(), String.t()) ::
              {:error, any()} | {:ok, map()}
  @callback conversations_list(String.t(), String.t() | atom(), number()) ::
              {:error, any()} | {:ok, map()}
  @callback conversations_replies(String.t(), SlackDB.Key.t(), String.t() | atom(), number()) ::
              {:error, any()} | {:ok, map()}

  @base_url "https://slack.com/api"

  @spec search_messages(String.t(), String.t(), keyword()) :: {:error, any()} | {:ok, map()}
  def search_messages(user_token, query, opts \\ []) do
    with {:ok, resp} <-
           client(user_token)
           |> post("/search.messages", %{
             query: query,
             highlight: false,
             sort: "timestamp",
             sort_dir: "desc",
             page: Keyword.get(opts, :page, 1)
             #  count: 2,
           }) do
      case resp.body |> Jason.decode!() do
        %{"ok" => true, "messages" => messages} -> {:ok, messages}
        %{"ok" => false, "error" => error} -> {:error, error}
        _ -> {:error, resp.status}
      end
    end
  end

  @spec chat_postMessage(String.t(), String.t(), String.t(), String.t() | atom()) ::
          {:error, any()} | {:ok, map()}
  def chat_postMessage(bot_token, text, channel_id, thread_ts \\ nil) do
    with {:ok, resp} <-
           client(bot_token)
           |> post(
             "/chat.postMessage",
             %{
               channel: channel_id,
               text: text,
               as_user: true,
               thread_ts: thread_ts
             }
           ) do
      case resp.body |> Jason.decode!() do
        %{"ok" => true} = body -> {:ok, body}
        %{"ok" => false, "error" => error} -> {:error, error}
        _ -> {:error, resp.status}
      end
    end
  end

  @spec chat_delete(String.t(), String.t(), String.t()) :: {:error, any()} | {:ok, map()}
  def chat_delete(user_token, channel_id, ts) do
    with {:ok, resp} <-
           client(user_token)
           |> post(
             "/chat.delete",
             %{
               channel: channel_id,
               ts: ts
             }
           ) do
      case resp.body |> Jason.decode!() do
        %{"ok" => true} = body -> {:ok, body}
        %{"ok" => false, "error" => error} -> {:error, error}
        _ -> {:error, resp.status}
      end
    end
  end

  @spec conversations_create(String.t(), String.t(), boolean()) :: {:error, any()} | {:ok, map()}
  def conversations_create(user_token, name, is_private?) do
    with {:ok, resp} <-
           client(user_token)
           |> post(
             "/conversations.create",
             %{
               name: name,
               validate: true,
               is_private: is_private?
             }
           ) do
      case resp.body |> Jason.decode!() do
        %{"ok" => true, "channel" => channel_info} -> {:ok, channel_info}
        %{"ok" => false, "error" => error} -> {:error, error}
        _ -> {:error, resp.status}
      end
    end
  end

  @spec conversations_archive(String.t(), String.t()) :: {:error, any()} | {:ok, map()}
  def conversations_archive(user_token, id) do
    with {:ok, resp} <-
           client(user_token)
           |> post(
             "/conversations.archive",
             %{channel: id}
           ) do
      case resp.body |> Jason.decode!() do
        %{"ok" => true} = body -> {:ok, body}
        %{"ok" => false, "error" => "already_archived"} -> {:ok, "already_archived"}
        %{"ok" => false, "error" => error} -> {:error, error}
        _ -> {:error, resp.status}
      end
    end
  end

  @spec conversations_invite(String.t(), String.t(), String.t()) :: {:error, any()} | {:ok, map()}
  def conversations_invite(user_token, channel_id, comma_seperated_user_ids)
      when is_binary(comma_seperated_user_ids) do
    with {:ok, resp} <-
           client(user_token)
           |> post(
             "/conversations.invite",
             %{channel: channel_id, users: comma_seperated_user_ids}
           ) do
      case resp.body |> Jason.decode!() do
        %{"ok" => true, "channel" => channel_info} -> {:ok, channel_info}
        %{"ok" => false, "error" => error} -> {:error, error}
        _ -> {:error, resp.status}
      end
    end
  end

  @spec conversations_list(String.t(), String.t() | atom(), number()) ::
          {:error, any()} | {:ok, map()}
  def conversations_list(user_token, cursor \\ nil, limit \\ 200) do
    with {:ok, resp} <-
           client(user_token)
           |> post("/conversations.list", %{
             exclude_archived: true,
             limit: limit,
             cursor: cursor,
             types: "public_channel,private_channel"
           }) do
      case resp.body |> Jason.decode!() do
        %{"ok" => true} = body -> {:ok, body}
        %{"ok" => false, "error" => error} -> {:error, error}
        _ -> {:error, resp.status}
      end
    end
  end

  # returns the most recent <limit_number> replies in chron order
  @spec conversations_replies(String.t(), SlackDB.Key.t(), String.t() | atom(), number()) ::
          {:error, any()} | {:ok, map()}
  def conversations_replies(user_token, key, cursor \\ nil, limit \\ 200) do
    with {:ok, resp} <-
           client(user_token)
           |> post("/conversations.replies", %{
             channel: key.channel_id,
             ts: key.ts,
             limit: limit,
             cursor: cursor
           }) do
      case resp.body |> Jason.decode!() do
        %{"ok" => true} = body -> {:ok, body}
        %{"ok" => false, "error" => error} -> {:error, error}
        _ -> {:error, resp.status}
      end
    end
  end

  defp client(token) do
    middleware = [
      {Tesla.Middleware.BaseUrl, @base_url},
      {Tesla.Middleware.Headers,
       [
         #  {"content-type", "application/x-www-form-urlencoded"},
         {"authorization", "Bearer " <> token}
       ]},
      {Tesla.Middleware.FormUrlencoded, []}
    ]

    Tesla.client(middleware)
  end

  defp parse_slack_response(resp, pull_key) do
    case resp.body |> Jason.decode!() do
      %{"ok" => true} = body -> {:ok, body}
      %{"ok" => false, "error" => error} -> {:error, error}
      _ -> {:error, resp.status}
    end
  end

  # def get_message(token, channel, ts) do
  #   with {:ok, resp} <-
  #          client(token)
  #          |> post("/channels.history", %{
  #            channel: channel,
  #            latest: ts,
  #            inclusive: true,
  #            count: 1
  #          }) do
  #     case resp.body |> Jason.decode!() do
  #       %{"ok" => true, "messages" => [message]} -> {:ok, message}
  #       %{"ok" => false, "error" => error} -> {:error, error}
  #       _ -> {:error, resp.status}
  #     end
  #   end
  # end

  # @spec reactions_get(String.t(), String.t(), String.t()) :: {:error, any()} | {:ok, map()}
  # def reactions_get(bot_token, channel_id, ts) do
  #   with {:ok, resp} <-
  #          client(bot_token)
  #          |> post(
  #            "/reactions.get",
  #            %{
  #              channel: channel_id,
  #              timestamp: ts,
  #              full: true
  #            }
  #          ) do
  #     case resp.body |> Jason.decode!() do
  #       %{"ok" => true} = body -> {:ok, body}
  #       %{"ok" => false, "error" => error} -> {:error, error}
  #       _ -> {:error, resp.status}
  #     end
  #   end
  # end

  # @spec conversations_join(String.t(), String.t()) :: {:error, any()} | {:ok, map()}
  # def conversations_join(user_token, channel_id) do
  #   with {:ok, resp} <-
  #          client(user_token)
  #          |> post(
  #            "/conversations.join",
  #            %{channel: channel_id}
  #          ) do
  #     case resp.body |> Jason.decode!() do
  #       %{"ok" => true, "channel" => channel_info} -> {:ok, channel_info}
  #       %{"ok" => false, "error" => error} -> {:error, error}
  #       _ -> {:error, resp.status}
  #     end
  #   end
  # end
end
