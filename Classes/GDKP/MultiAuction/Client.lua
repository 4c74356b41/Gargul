---@type GL
local _, GL = ...;

---@class GDKPMultiAuctionClient
GL:tableSet(GL, "GDKP.MultiAuction.Client", {
    _initialized = false,
    detailsChanged = false,

    AuctionDetails = {},
});

---@type GDKPMultiAuctionClient
local Client = GL.GDKP.MultiAuction.Client;

---@type GDKPMultiAuctionAuctioneer
local Auctioneer = GL.GDKP.MultiAuction.Auctioneer;

---@type GDKPMultiAuctionClientInterface
local UI;

--[[ CONSTANTS ]]
local ENDS_AT_OFFSET = 1697932800;

---@return void
function Client:_init()
    if (self._initialized) then
        return;
    end

    UI = GL.Interface.GDKP.MultiAuction.Client;

    self._initialized = true;
end

--- This is used to determine which session to take over / participate in
--- when joining a group or logging (back) into the game
--- /dump _G.Gargul.GDKP.MultiAuction.Client:currentSessionHash();
---
---@return string
function Client:currentSessionHash()
    if (type(self.AuctionDetails.Auctions) ~= "table"
        or GL:empty(self.AuctionDetails.Auctions)
    ) then
        return;
    end

    local BidDetails = (function()
        local Result = {};

        for id, Details in pairs(self.AuctionDetails.Auctions or {}) do
            Result[id] = GL:implode({
                Details.link,
                GL:tableGet(Details, "CurrentBid.amount"),
                GL:tableGet(Details, "CurrentBid.player"),
            }, "-");
        end

        return Result;
    end)();

    return GL:implode({
        tonumber(self.AuctionDetails.antiSnipe) or 0,
        strlower(self.AuctionDetails.initiator),
        GL:stringHash(BidDetails)
    }, ".");
end

---@return void
function Client:start(Message)
    -- Make sure that whoever sent us this message is actually allowed to start a multi-auction
    if (not Auctioneer:userIsAllowedToBroadcast(GL:tableGet(Message, "Sender.id", ""))) then
        return;
    end

    self.AuctionDetails = {
        initiator = Message.Sender.fqn,
        antiSnipe = Message.content.antiSnipe,
        bth = Message.content.bth,
        Auctions = {},
    };

    local activeAuctions = false;
    local serverTime = GetServerTime();
    for _, Item in pairs(GL:tableGet(Message, "content.ItemDetails", {})) do
        self.AuctionDetails.Auctions[Item.auctionID] = Item;

        if (serverTime < Item.endsAt) then
            activeAuctions = true;
        end
    end

    UI:clear();

    UI:open();
    UI:refresh();

    GL:after(.1, nil, function ()
        UI.showFavorites = true;
        UI.showUnusable = false;
        UI.ToggleFavorites:GetScript("OnClick")();
        UI.ToggleUnusable:GetScript("OnClick")();
    end);

    -- Looks like there are no active auctions, this can happen when joining a new group with expired data
    if (not activeAuctions) then
        UI:close();
    end
end

---@param link table|string item link
---@param duration number
---@param minimum number
---@param increment number
---@return void
function Client:addToCurrentSession(link, duration, minimum, increment)
    if (duration ~= nil or type(link) ~= "table") then
        GL:error("Pass a table instead of multiple arguments")
        return;
    end

    if (not Auctioneer:auctionStartedByMe()
        or GL:empty(self.AuctionDetails.Auctions)
    ) then
        return;
    end

    duration = link.duration;
    minimum = link.minimum;
    increment = link.increment;

    link = link.link;

    local lastAuctionID = 0;
    for id in pairs(GL:tableColumn(self.AuctionDetails.Auctions, "auctionID") or {}) do
        if (id > lastAuctionID) then
            lastAuctionID = lastAuctionID + 1;
        end
    end
    lastAuctionID = lastAuctionID + 1;

    GL:onItemLoadDo(link, function (Item)
        if (not Item) then
            return;
        end

        self.AuctionDetails.Auctions[lastAuctionID] = {
            auctionID = lastAuctionID,
            isBOE = GL:inTable({ LE_ITEM_BIND_ON_EQUIP, LE_ITEM_BIND_QUEST }, Item.bindType),
            itemLevel = Item.level,
            name = Item.name,
            quality = Item.quality,
            link = Item.link,
            minimum = minimum,
            increment = increment,
            endsAt = GetServerTime() + duration,
        };

        Auctioneer.IDsToAnnounce[lastAuctionID] = true;
        Auctioneer.detailsChanged = true;

        GL:after(1.15, "GDKP.MultiAuction.syncNewItems", function ()
            Auctioneer:syncNewItems();
        end);
    end);
end

---@param auctionID number
---@param amount number
function Client:bid(auctionID, amount)
    if (Auctioneer:auctionStartedByMe(auctionID)) then
        Auctioneer:processBid({
            Sender = {
                fqn = GL.User.fqn,
                isSelf = true,
            },
            content = {
                auctionID = auctionID,
                bid = amount,
            }
        });

        return;
    end

    GL.CommMessage.new(
        GL.Data.Constants.Comm.Actions.bidOnGDKPMultiAuction,
        { auctionID = auctionID, bid = amount, },
        "WHISPER",
        self.AuctionDetails.initiator
    ):send();
end

--- The loot master sent us an update of all top bids, refresh our UI
---
---@param Message CommMessage
---@return void
function Client:updateBids(Message)
    if (not self.AuctionDetails
        or self.AuctionDetails.initiator ~= Message.Sender.fqn
    ) then
        return;
    end

    for auctionID, Details in pairs(Message.content or {}) do
        (function()
            if (not Message.Sender.isSelf and Details.I) then
                self.AuctionDetails.Auctions[auctionID] = Details.I;
                self.AuctionDetails.Auctions[auctionID].CurrentBid = Details.CurrentBid or {};

                GL:after(.2, "GDKP.MultiAuction.refreshUI", function ()
                    UI:refresh(true);
                end);
            end

            if (not GL:tableGet(self.AuctionDetails, "Auctions." .. auctionID)) then
                return;
            end

            local amount = Details.a * 1000;
            local bidder = Details.p;
            local bidderIsMe = GL:iEquals(bidder, GL.User.fqn);

            -- The auctioneer already did this on his end before sending it to us
            if (not Message.Sender.isSelf) then
                -- There are no bids
                if (amount < 1) then
                    Client.AuctionDetails.Auctions[auctionID].iWasOutBid = false;

                -- We're top bidder again
                elseif (Client.AuctionDetails.Auctions[auctionID].iWasOutBid
                    and bidderIsMe
                ) then
                    Client.AuctionDetails.Auctions[auctionID].iWasOutBid = false;

                -- We were top bidder but not anymore
                elseif (not Client.AuctionDetails.Auctions[auctionID].iWasOutBid
                    and not bidderIsMe
                    and GL:iEquals(GL:tableGet(Client.AuctionDetails.Auctions[auctionID], "CurrentBid.player", ""), GL.User.fqn)
                ) then
                    Client:outbidNotification();

                    Client.AuctionDetails.Auctions[auctionID].iWasOutBid = true;
                end
            end

            if (amount > 0) then
                self.AuctionDetails.Auctions[auctionID].CurrentBid = {
                    amount = amount,
                    player = bidder,
                };
            else
                self.AuctionDetails.Auctions[auctionID].CurrentBid = nil;
            end

            if (Details.e) then
                self.AuctionDetails.Auctions[auctionID].endsAt = Details.e > 0 and Details.e + ENDS_AT_OFFSET or Details.e;
            end
        end)();
    end

    UI:refresh();
end

--- Check if the given bid is valid for the given auction ID
---
---@param auctionID string
---@param bid number
---@return boolean
function Client:isBidValidForAuction(auctionID, bid)
    bid = tonumber(bid) or 0;
    if (bid < 1) then
        return false;
    end

    local Auction = GL:tableGet(self.AuctionDetails, "Auctions." .. auctionID);
    if (not Auction) then
        return false;
    end

    local currentBid = GL:tableGet(Auction, "CurrentBid.amount", 0);
    return (currentBid == 0 and bid >= Auction.minimum) or bid >= currentBid + Auction.increment;
end

--- Return the minimum bid for the give auction
---
---@param auctionID number
---@return number
function Client:minimumBidForAuction(auctionID)
    local Auction = GL:tableGet(self.AuctionDetails, "Auctions." .. auctionID);
    if (not Auction) then
        return 0;
    end

    local currentBid = GL:tableGet(Auction, "CurrentBid.amount");
    return currentBid and currentBid + Auction.increment or Auction.minimum;
end

--- Let the user know that he was outbid
---
---@return void
function Client:outbidNotification()
    -- Flash the game icon in case the player alt-tabbed
    FlashClientIcon();

    -- Play a sound if the user enabled it
    local outbidSound = GL.Settings:get("GDKP.outbidSound");
    if (GL:empty(outbidSound)) then
        return;
    end

    GL:after(2, "GDKP.MultiAuction.OutbidNotification", function ()
        local sound = LibStub("LibSharedMedia-3.0"):Fetch("sound", outbidSound);
        GL:playSound(sound);
    end);
end