import asyncdispatch, json, options
import ../objects, ../constants, ../helpers
import tables, sequtils
import uri, macros, requester

proc triggerTypingIndicator*(api: RestApi, channel_id: string) {.async.} =
    ## Starts typing in a specific Discord channel.
    discard await api.request("POST", endpointTriggerTyping(channel_id))

proc addChannelMessagePin*(api: RestApi,
        channel_id, message_id: string; reason = "") {.async.} =
    ## Add pinned message.
    discard await api.request(
        "PUT",
        endpointChannelPins(channel_id, message_id),
        audit_reason = reason
    )

proc deleteChannelMessagePin*(api: RestApi,
        channel_id, message_id: string; reason = "") {.async.} =
    ## Remove pinned message.
    discard await api.request(
        "DELETE",
        endpointChannelPins(channel_id, message_id),
        audit_reason = reason
    )

proc getChannelPins*(api: RestApi,
        channel_id: string): Future[seq[Message]] {.async.} =
    ## Get channel pins.
    result = (await api.request(
        "GET",
        endpointChannelPins(channel_id)
    )).elems.map(newMessage)


proc editGuildChannel*(api: RestApi, channel_id: string;
            name, parent_id, topic = none string;
            rate_limit_per_user = none range[0..21600];
            bitrate = none range[8000..128000]; user_limit = none range[0..99];
            position = none int; permission_overwrites = none seq[Overwrite];
            nsfw = none bool; reason = ""): Future[GuildChannel] {.async.} =
    ## Modify a guild channel.
    let payload = newJObject()

    if name.isSome:
        assert name.get.len >= 2 and name.get.len <= 100
    if topic.isSome:
        assert topic.get.len <= 1024

    payload.loadOpt(name, position, topic, nsfw, rate_limit_per_user,
        bitrate, user_limit, permission_overwrites, parent_id)

    payload.loadNullableOptStr(topic, parent_id)
    payload.loadNullableOptInt(position, rate_limit_per_user, bitrate,
        user_limit)

    result = (await api.request(
        "PATCH",
        endpointChannels(channel_id),
        $payload,
        audit_reason = reason
    )).newGuildChannel

proc createGuildChannel*(api: RestApi, guild_id, name: string; kind = 0;
            parent_id, topic = none string; nsfw = none bool;
            rate_limit_per_user, bitrate, position, user_limit = none int;
            permission_overwrites = none seq[Overwrite];
            reason = ""): Future[GuildChannel] {.async.} =
    ## Creates a channel.
    let payload = %*{"name": name, "type": kind}

    payload.loadOpt(position, topic, nsfw, rate_limit_per_user,
                    bitrate, user_limit, parent_id, permission_overwrites)

    result = (await api.request(
        "POST",
        endpointGuildChannels(guild_id),
        $payload
    )).newGuildChannel

proc deleteChannel*(api: RestApi, channel_id: string; reason = "") {.async.} =
    ## Deletes or closes a channel.
    discard await api.request(
        "DELETE",
        endpointChannels(channel_id),
        audit_reason = reason
    )

proc editGuildChannelPermissions*(api: RestApi,
        channel_id, perm_id, kind: string or int;
        perms: PermObj; reason = "") {.async.} =
    ## Modify the channel's permissions.
    ## 
    ## - `kind` Must be "role" or "member", or 0 or 1 if v8.
    let payload = newJObject()

    when kind is int and not defined(discordv8):
        payload["type"] = %(if kind == 0: "role" else: "member") 

    when kind is string and defined(discordv8):
        payload["type"] = %(if kind == "role": 0 else: 1)

    if perms.allowed.len > 0:
        payload["allow"] = %(cast[int](perms.allowed))
    if perms.denied.len > 0:
        payload["deny"] = %(cast[int](perms.denied))

    discard await api.request(
        "PUT",
        endpointChannelOverwrites(channel_id, perm_id),
        $payload,
        audit_reason = reason
    )

proc createChannelInvite*(api: RestApi, channel_id: string;
        max_age = 86400; max_uses = 0;
        temp, unique = false; target_user = none string;
        target_user_type = none int; reason = ""): Future[Invite] {.async.} =
    ## Creates an instant invite.
    let payload = %*{
        "max_age": max_age,
        "max_uses": max_uses,
        "temp": temp,
        "unique": unique,
    }
    payload.loadOpt(target_user, target_user_type)

    result = (await api.request(
        "POST",
        endpointChannelInvites(channel_id),
        $payload,
        audit_reason = reason
    )).newInvite

proc deleteGuildChannelPermission*(api: RestApi, channel_id, overwrite: string;
        reason = "") {.async.} =
    ## Deletes a guild channel overwrite.
    discard await api.request(
        "DELETE",
        endpointChannelOverwrites(channel_id, overwrite),
        audit_reason = reason
    )

proc deleteInvite*(api: RestApi, code: string; reason = "") {.async.} =
    ## Deletes a guild invite.
    discard await api.request(
        "DELETE",
        endpointInvites(code),
        audit_reason = reason
    )

proc getChannelInvites*(api: RestApi,
        channel_id: string): Future[seq[Invite]] {.async.} =
    ## Gets a list of a channel's invites.
    result = (await api.request(
        "GET",
        endpointChannelInvites(channel_id)
    )).elems.map(newInvite)

proc getChannel*(api: RestApi,
        channel_id: string): Future[(Option[GuildChannel], Option[DMChannel])] {.async.} =
    ## Gets channel by ID.
    ## 
    ## Another thing to keep in mind is that it returns a tuple of each
    ## possible channel as an option.
    ## 
    ## Example:
    ## - `channel` Is the result tuple, returned after `await`ing getChannel.
    ## - If you want to get guild channel, then do `channel[0]`
    ## - OR if you want DM channel then do `channel[1]`
    let data = (await api.request(
        "GET",
        endpointChannels(channel_id)
    ))
    if data["type"].getInt == int ctDirect:
        result = (none GuildChannel, some newDMChannel(data))
    else:
        result = (some newGuildChannel(data), none DMChannel)

proc getGuildChannels*(api: RestApi,
        guild_id: string): Future[seq[GuildChannel]] {.async.} =
    ## Gets a list of a guild's channels
    result = (await api.request(
        "GET",
        endpointGuildChannels(guild_id)
    )).elems.map(newGuildChannel)

proc editGuildChannelPositions*(api: RestApi, guild_id, channel_id: string;
        position = none int; parent_id = none string; lock_permissions = false;
        reason = "") {.async.} =
    ## Edits a guild channel's position.
    let payload = %*{
        "id": channel_id,
        "position": %position,
        "parent_id": %parent_id,
        "lock_permissions": lock_permissions
    }
    payload.loadNullableOptStr(parent_id)
    discard await api.request(
        "PATCH",
        endpointGuildChannels(guild_id, channel_id),
        $payload,
        audit_reason = reason
    )

proc getChannelWebhooks*(api: RestApi,
        channel_id: string): Future[seq[Webhook]] {.async.} =
    ## Gets a list of a channel's webhooks.
    result = (await api.request(
        "GET",
        endpointChannelWebhooks(channel_id)
    )).elems.map(newWebhook)

proc createWebhook*(api: RestApi, channel_id, username: string;
        avatar = none string; reason = ""): Future[Webhook] {.async.} =
    ## Creates a webhook.
    ## (webhook names cannot be: 'clyde', and they range 1-80)
    result = (await api.request(
        "POST",
        endpointChannelWebhooks(channel_id),
        if avatar.isNone: $(%*{"name": username})
        else: $(%*{"name": username, "avatar": avatar.get}),
        audit_reason = reason
    )).newWebhook

proc getWebhook*(api: RestApi, webhook_id: string): Future[Webhook] {.async.} =
    ## Gets a webhook.
    result = (await api.request("GET", endpointWebhooks(webhook_id))).newWebhook

proc deleteWebhook*(api: RestApi, webhook_id: string; reason = "") {.async.} =
    ## Deletes a webhook.
    discard await api.request(
        "DELETE",
        endpointWebhooks(webhook_id),
        audit_reason = reason
    )

proc editWebhook*(api: RestApi, webhook_id: string;
        name, avatar, channel_id = none string; reason = "") {.async.} =
    ## Modifies a webhook.
    let payload = newJObject()

    payload.loadOpt(name, avatar, channel_id)
    payload.loadNullableOptStr(avatar)

    discard await api.request("PATCH",
        endpointWebhooks(webhook_id),
        $payload,
        audit_reason = reason
    )
