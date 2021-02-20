local _, App = ...;

App.Auctioneer = App.Auctioneer or {};
App.AuctioneerUI = App.AuctioneerUI or {};
App.Ace.ScrollingTable = App.Ace.ScrollingTable or LibStub("ScrollingTable");

local Settings = App.Settings;
local AceGUI = App.Ace.GUI;
local AuctioneerUI = App.AuctioneerUI;
local ScrollingTable = App.Ace.ScrollingTable;

AuctioneerUI.Defaults = {
    itemIcon = "Interface\\Icons\\INV_Misc_QuestionMark",
    itemBoxText = "",
    minimumBid = 10,
    timer = 25,
};

AuctioneerUI.Widgets = {
    Frame = {},
    Buttons = {},
    EditBoxes = {},
    Labels = {},
    Tables = {},
    Icons = {},
};
AuctioneerUI.ItemPriorityBox = {};
AuctioneerUI.ItemBoxHoldsValidItem = false;

AuctioneerUI.BidTable = {};

-- This is the UI the auctioneer uses to prepare the auction e.g:
-- Select an item
-- Set a minimum bid value
-- Set the duration of the auction
-- Keep track of bids
-- Award the item to the winner
function AuctioneerUI:draw(itemLink)
    App:debug("AuctioneerUI:draw");

    -- First we need to check if the frame hasn't been
    -- rendered already. If so then show it (if it's hidden)
    -- and pass the itemLink along in case one was provided
    if (AuctioneerUI.Widgets.Frame
            and AuctioneerUI.Widgets.Frame.rendered
    ) then
        if (itemLink) then
            self:passItemLink(itemLink);
        end

        -- If the frame is hidden we need to show it again
        if (not self.Widgets.Frame:IsShown()) then
            self.Widgets.Frame:Show();
        end

        return;
    end

    -- Create a container/parent frame
    local AuctioneerFrame = AceGUI:Create("Frame");
    AuctioneerFrame:SetTitle("Gargul v" .. App.version);
    AuctioneerFrame:SetLayout("Flow");
    AuctioneerFrame:SetWidth(430);
    AuctioneerFrame:SetHeight(350);
    AuctioneerFrame:EnableResize(false);
    AuctioneerFrame.rendered = true;
    AuctioneerFrame.frame:SetFrameStrata("HIGH");
    AuctioneerFrame.statustext:GetParent():Hide(); -- Hide the statustext bar
    AuctioneerFrame:SetCallback("OnClose", function(widget)
        local point, _, relativePoint, offsetX, offsetY = AuctioneerFrame:GetPoint();

        -- Store the frame's last position for future play sessions
        Settings:set("UI.Auctioneer.Position.point", point);
        Settings:set("UI.Auctioneer.Position.relativePoint", relativePoint);
        Settings:set("UI.Auctioneer.Position.offsetX", offsetX);
        Settings:set("UI.Auctioneer.Position.offsetY", offsetY);
    end);
    AuctioneerFrame:SetPoint(
        Settings:get("UI.Auctioneer.Position.point"),
        UIParent,
        Settings:get("UI.Auctioneer.Position.relativePoint"),
        Settings:get("UI.Auctioneer.Position.offsetX"),
        Settings:get("UI.Auctioneer.Position.offsetY")
    );

    self.Widgets.Frame = AuctioneerFrame;

            --[[
                FIRST ROW (ITEM ICON AND LINK BOX)
            ]]

            local FirstRow = AceGUI:Create("SimpleGroup");
            FirstRow:SetLayout("Flow");
            FirstRow:SetFullWidth(true);
            FirstRow:SetHeight(30);
            AuctioneerFrame:AddChild(FirstRow);

                    --[[
                        ITEM ICON
                    ]]

                    local ItemIcon = AceGUI:Create("Icon");
                    ItemIcon:SetImage("Interface\\Icons\\INV_Misc_QuestionMark");
                    ItemIcon:SetImageSize(30, 30);
                    ItemIcon:SetWidth(40);
                    FirstRow:AddChild(ItemIcon);
                    self.Widgets.Icons.Item = ItemIcon;

                    --[[
                        ITEM TEXTBOX
                    ]]
                    local ItemBox = AceGUI:Create("EditBox");

                    ItemBox:DisableButton(true);
                    ItemBox:SetHeight(20);
                    ItemBox:SetWidth(170);
                    ItemBox:SetCallback("OnTextChanged", self.ItemBoxChanged); -- Update item info when input value changes
                    ItemBox:SetCallback("OnEnterPressed", self.ItemBoxChanged); -- Update item info when item is dragged on top (makes no sense to use OnEnterPressed I know)

                    self.Widgets.EditBoxes.Item = ItemBox;

                    FirstRow:AddChild(ItemBox);

                    -- Show a gametooltip if the icon shown belongs to an item
                    ItemIcon:SetCallback("OnEnter", function()
                        if (not self.ItemBoxHoldsValidItem) then
                            return;
                        end

                        local itemLink = ItemBox:GetText();
                        GameTooltip:SetOwner(ItemIcon.frame, "ANCHOR_TOP");
                        GameTooltip:SetHyperlink(itemLink);
                        GameTooltip:Show();
                    end)

                    ItemIcon:SetCallback("OnLeave", function()
                        GameTooltip:Hide();
                    end)

                    --[[
                        BUTTON PADDER
                        CONTAINER FOR PADDING PURPOSES ONLY
                    ]]

                    local ButtonPadder = AceGUI:Create("SimpleGroup");
                    ButtonPadder:SetLayout("Flow");
                    ButtonPadder:SetWidth(20);
                    ButtonPadder:SetHeight(30);
                    FirstRow:AddChild(ButtonPadder);

                    --[[
                        START/STOP BUTTON
                    ]]

                    local StartButton = AceGUI:Create("Button");
                    StartButton:SetText("Start");
                    StartButton:SetWidth(80);
                    StartButton:SetHeight(20);
                    StartButton:SetDisabled(true);
                    StartButton:SetCallback("OnClick", function()
                        App.Auction.inProgress = true;

                        App.Auction:announceStart(
                            self.Widgets.EditBoxes.Item:GetText(),
                            self.Widgets.EditBoxes.MinimumBid:GetText(),
                            self.Widgets.EditBoxes.Timer:GetText()
                        );

                        self:updateWidgets();
                    end);
                    FirstRow:AddChild(StartButton);
                    self.Widgets.Buttons.StartButton = StartButton;

                    --[[
                        STOP BUTTON
                    ]]

                    local StopButton = AceGUI:Create("Button");
                    StopButton:SetText("Stop");
                    StopButton:SetWidth(80);
                    StopButton:SetHeight(20);
                    StopButton:SetDisabled(true);
                    StopButton:SetCallback("OnClick", function()
                        App.Auction:announceStop();
                    end);
                    FirstRow:AddChild(StopButton);
                    self.Widgets.Buttons.StopButton = StopButton;

            --[[
                SECOND ROW
            ]]

            local SecondRow = AceGUI:Create("SimpleGroup");
            SecondRow:SetLayout("Flow");
            SecondRow:SetFullWidth(true);
            SecondRow:SetHeight(20);
            AuctioneerFrame:AddChild(SecondRow);

                    --[[
                        SPACER
                    ]]

                    local PreItemPrioSpacer = AceGUI:Create("SimpleGroup");
                    PreItemPrioSpacer:SetLayout("Flow");
                    PreItemPrioSpacer:SetWidth(8);
                    PreItemPrioSpacer:SetHeight(20);
                    SecondRow:AddChild(PreItemPrioSpacer);

                    --[[
                        ITEM PRIO
                    ]]

                    local ItemPrio = AceGUI:Create("Label");
                    ItemPrio:SetColor(.94, .72, .8);
                    ItemPrio:SetHeight(20);
                    ItemPrio:SetWidth(150);
                    SecondRow:AddChild(ItemPrio);
                    self.Widgets.Labels.ItemPriority = ItemPrio;

            --[[
                THID ROW (ITEM ICON AND LINK BOX)
            ]]

            local ThirdRow = AceGUI:Create("SimpleGroup");
            ThirdRow:SetLayout("Flow");
            ThirdRow:SetFullWidth(true);
            ThirdRow:SetHeight(20);
            AuctioneerFrame:AddChild(ThirdRow);

                    --[[
                        SPACER
                    ]]

                    local PreMinimumBidLabelSpacer = AceGUI:Create("SimpleGroup");
                    PreMinimumBidLabelSpacer:SetLayout("Flow");
                    PreMinimumBidLabelSpacer:SetWidth(8);
                    PreMinimumBidLabelSpacer:SetHeight(20);
                    ThirdRow:AddChild(PreMinimumBidLabelSpacer);

                    --[[
                        MINIMUM BID LABEL
                    ]]

                    local MinimumBidLabel = AceGUI:Create("Label");
                    MinimumBidLabel:SetText("MINIMUM BID");
                    MinimumBidLabel:SetHeight(20);
                    MinimumBidLabel:SetWidth(80);
                    ThirdRow:AddChild(MinimumBidLabel);
                    self.Widgets.Labels.MinimumBidLabel = MinimumBidLabel;

                    --[[
                        MINIMUM BID TEXTBOX
                    ]]

                    local MinimumBidBox = AceGUI:Create("EditBox");
                    MinimumBidBox:DisableButton(true);
                    MinimumBidBox:SetHeight(20);
                    MinimumBidBox:SetWidth(40);
                    MinimumBidBox:SetText("10");
                    ThirdRow:AddChild(MinimumBidBox);
                    self.Widgets.EditBoxes.MinimumBid = MinimumBidBox;

                    --[[
                        SPACER
                    ]]

                    local BidAndTimerSpacer = AceGUI:Create("SimpleGroup");
                    BidAndTimerSpacer:SetLayout("Flow");
                    BidAndTimerSpacer:SetWidth(10);
                    BidAndTimerSpacer:SetHeight(30);
                    ThirdRow:AddChild(BidAndTimerSpacer);

                    --[[
                        TIMER LABEL
                    ]]

                    local TimerLabel = AceGUI:Create("Label");
                    TimerLabel:SetText("TIMER (s)");
                    TimerLabel:SetHeight(20);
                    TimerLabel:SetWidth(55);
                    ThirdRow:AddChild(TimerLabel);
                    self.Widgets.Labels.TimerLabel = TimerLabel;

                    --[[
                        TIMER TEXTBOX
                    ]]

                    local TimerBox = AceGUI:Create("EditBox");
                    TimerBox:DisableButton(true);
                    TimerBox:SetHeight(20);
                    TimerBox:SetWidth(40);
                    TimerBox:SetText("25");
                    ThirdRow:AddChild(TimerBox);
                    self.Widgets.EditBoxes.Timer = TimerBox;

                    --[[
                        SPACER
                    ]]

                    local TimerAndAwardSpacer = AceGUI:Create("SimpleGroup");
                    TimerAndAwardSpacer:SetLayout("Flow");
                    TimerAndAwardSpacer:SetWidth(20);
                    TimerAndAwardSpacer:SetHeight(30);
                    ThirdRow:AddChild(TimerAndAwardSpacer);

                    --[[
                        RESET BUTTON
                    ]]
                    local ClearButton = AceGUI:Create("Button");
                    ClearButton:SetText("Clear");
                    ClearButton:SetWidth(66);
                    ClearButton:SetHeight(20);
                    ClearButton:SetDisabled(false);
                    ClearButton:SetCallback("OnClick", function()
                        StaticPopup_Show("CLEAR_AUCTION_CONFIRMATION");
                    end);
                    ThirdRow:AddChild(ClearButton);
                    self.Widgets.Buttons.ClearButton = ClearButton;

                    --[[
                        AWARD BUTTON
                    ]]

                    local AwardButton = AceGUI:Create("Button");
                    AwardButton:SetText("Award");
                    AwardButton:SetWidth(70);
                    AwardButton:SetHeight(20);
                    AwardButton:SetDisabled(true);
                    AwardButton:SetCallback("OnClick", function()
                        local BidsTable = self.Widgets.Tables.Bids;
                        local selected = BidsTable:GetRow(BidsTable:GetSelection());

                        if (not selected
                            or not type(selected) == "table"
                        ) then
                            return App:warning("You need to select a bid first");
                        end

                        return App.Auction:award(unpack(selected));
                    end);
                    ThirdRow:AddChild(AwardButton);
                    self.Widgets.Buttons.AwardButton = AwardButton;

            --[[
                FOURTH ROW (BIDS)
            ]]

            local FourthRow = AceGUI:Create("SimpleGroup");
            FourthRow:SetLayout("Flow");
            FourthRow:SetFullWidth(true);
            FourthRow:SetHeight(50);
            AuctioneerFrame:AddChild(FourthRow);

            self:drawBidsTable(AuctioneerFrame.frame);

    if (itemLink
            and type(itemLink) == "string"
    ) then
        self:passItemLink(itemLink);
    end
end

function AuctioneerUI:ItemBoxChanged()
    App:debug("AuctioneerUI:ItemBoxChanged");

    local itemLink = AuctioneerUI.Widgets.EditBoxes.Item:GetText();

    AuctioneerUI:passItemLink(itemLink);
end

-- Pass an item link to the master looter UI
-- This method is used when alt clicking an item
-- in a loot window or when executing /gl roll [itemlink]
function AuctioneerUI:passItemLink(itemLink)
    App:debug("AuctioneerUI:passItemLink");

    if (not self.Widgets.Frame.rendered) then

        return;
    end

    if (App.Auction.inProgress) then
        return App:warning("An auction currently in progress");
    end

    self.Widgets.EditBoxes.Item:SetText(itemLink);
    return self:update();
end

-- Update the master looter UI based on the value of the ItemBox input
function AuctioneerUI:update()
    App:debug("AuctioneerUI:update");

    local IconWidget = self.Widgets.Icons.Item;
    local itemLink = self.Widgets.EditBoxes.Item:GetText();

    -- If the item link is not valid then
    --   Show the default question mark icon
    --   Remove the item priority string
    if (not itemLink or itemLink == "") then
        App:debug("AuctioneerUI:update. Item link is invalid");

        self.ItemBoxHoldsValidItem = false;
        IconWidget:SetImage(self.Defaults.itemIcon);

        return self:updateWidgets();
    end

    -- The item's icon is in the 10th position
    local icon = select(10, GetItemInfo(itemLink));

    if (icon) then
        self.Widgets.Tables.Bids:ClearSelection();
        self.Widgets.Tables.Bids:SetData({}, true);

        IconWidget:SetImage(icon);
        self.ItemBoxHoldsValidItem = true;
    else
        self.ItemBoxHoldsValidItem = false;
        IconWidget:SetImage(self.Defaults.itemIcon);
    end

    self:updateWidgets();
end

function AuctioneerUI:drawBidsTable(parent)
    App:debug("AuctioneerUI:drawBidsTable");

    local columns = {
        {
            name = "Player",
            width = 170,
            align = "LEFT",
            color = {
                r = 0.5,
                g = 0.5,
                b = 1.0,
                a = 1.0
            },
            colorargs = nil,
        },
        {
            name = "Bid",
            width = 85,
            align = "LEFT",
            color = {
                r = 0.5,
                g = 0.5,
                b = 1.0,
                a = 1.0
            },
            colorargs = nil,
            sort = 2, -- 1 = ascending, 2 = descending
        },
        {
            name = "Total DKP",
            width = 85,
            align = "LEFT",
            color = {
                r = 0.5,
                g = 0.5,
                b = 1.0,
                a = 1.0
            },
            colorargs = nil,
        },
    };

    local table = ScrollingTable:CreateST(columns, 8, 15, nil, parent);
    table:EnableSelection(true);
    table.frame:SetPoint("BOTTOM", parent, "BOTTOM", 0, 50);

    self.Widgets.Tables.Bids = table;
end

-- Update the icon box based on the value of the ItemBox input
function AuctioneerUI:updateItemIcon()
    App:debug("AuctioneerUI:updateItemIcon");

    local IconWidget = self.Widgets.Icons.Item;
    local itemLink = self.Widgets.EditBoxes.Item:GetText();

    if (not itemLink or itemLink == "") then
        self.ItemBoxHoldsValidItem = false;
        IconWidget:SetImage("Interface\\Icons\\INV_Misc_QuestionMark");
        return;
    end

    -- The item's icon is in the 10th position
    local icon = select(10, GetItemInfo(itemLink));

    if (icon) then
        if (App.Auction.CurrentAuction.itemLink
                and itemLink ~= App.Auction.CurrentAuction.itemLink
        ) then
            AuctioneerUI.Widgets.Tables.Bids:ClearSelection();
            AuctioneerUI.Widgets.Tables.Bids:SetData({}, true);
        end

        IconWidget:SetImage(icon);
        self.ItemBoxHoldsValidItem = true;
    else
        self.ItemBoxHoldsValidItem = false;
        IconWidget:SetImage("Interface\\Icons\\INV_Misc_QuestionMark");
    end
end

-- Update the item priority string
function AuctioneerUI:updateItemPriority(ItemPriorityBox, itemLink)
    local ItemPriorityBox = self.Widgets.Labels.ItemPriority;
    local itemLink = self.Widgets.EditBoxes.Item:GetText();

    App:debug("AuctioneerUI:updateItemPriority");

    if (not self.ItemBoxHoldsValidItem) then
        ItemPriorityBox:SetText("");
        return;
    end

    local itemPriority = App.LootPriority:getPriorityByItemLink(itemLink);

    if (not itemPriority) then
        ItemPriorityBox:SetText("Off spec");
    else
        itemPriority = table.concat(itemPriority, " > ");
        ItemPriorityBox:SetText(itemPriority);
    end
end

-- Reset the auctioneer's UI to its defaults
function AuctioneerUI:reset()
    self.Widgets.Icons.Item:SetImage(self.Defaults.itemIcon);
    self.Widgets.EditBoxes.Item:SetText(self.Defaults.itemText);
    self.Widgets.EditBoxes.MinimumBid:SetText(self.Defaults.minimumBid);
    self.Widgets.EditBoxes.Timer:SetText(self.Defaults.timer);
    self.Widgets.Labels.ItemPriority:SetText("");
    self.ItemBoxHoldsValidItem = false;

    self.Widgets.Tables.Bids:ClearSelection();
    self.Widgets.Tables.Bids:SetData({}, true);

    self:updateWidgets();
end

-- Update the widgets based on the current state of the auction
function AuctioneerUI:updateWidgets()
    App:debug("AuctioneerUI:updateWidgets");

    -- If the itembox doesn't hold a valid item link then
    -- The start button should not be available
    -- The stop button should be available
    -- The item box should be available
    if (not self.ItemBoxHoldsValidItem or not App.User.isInGroup) then
        self.Widgets.Buttons.StartButton:SetDisabled(true);
        self.Widgets.Buttons.StartButton:SetDisabled(true);
        self.Widgets.Buttons.StopButton:SetDisabled(true);
        self.Widgets.EditBoxes.Item:SetDisabled(false);

        return;
    end

    -- The value in the itembox is valid (e.g. contains a valid item link)

    -- If no auction is currently in progress then:
    -- The start button should be available
    -- The stop button should not be available
    -- The item box should be available so we can enter an item link
    if (not App.Auction.inProgress) then
        self.Widgets.Buttons.StartButton:SetDisabled(false);
        self.Widgets.Buttons.AwardButton:SetDisabled(false);
        self.Widgets.Buttons.StopButton:SetDisabled(true);
        self.Widgets.Buttons.ClearButton:SetDisabled(false);
        self.Widgets.EditBoxes.Item:SetDisabled(false);

    -- If an auction is currently in progress then:
        -- The start button should not be available
        -- The stop button should be available
        -- The item box should not be available
    else
        self.Widgets.Buttons.StartButton:SetDisabled(true);
        self.Widgets.Buttons.AwardButton:SetDisabled(true);
        self.Widgets.Buttons.StopButton:SetDisabled(false);
        self.Widgets.Buttons.ClearButton:SetDisabled(true);
        self.Widgets.EditBoxes.Item:SetDisabled(true);
    end
end

App:debug("AuctioneerUI.lua");