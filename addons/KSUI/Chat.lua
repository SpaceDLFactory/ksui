-- Chat: channel names cut to their bare name ("[1. 공개 - 티리스팔 숲]" becomes "[공개]"), web addresses made into
-- links that open a box to copy them from, and a sound when someone whispers you. Chat lines can be secret during
-- encounters; those are passed on untouched.

local _, ns = ...

local LINK_TYPE = "ksuiurl"
local URL_COLOR = "ff4da6ff"
local URL_PATTERNS = { "https?://[%w%-%.:_/%%%?&=#~+]+", "www%.[%w%-]+%.[%w%-%.:_/%%%?&=#~+]+" }

local function shortenChannels(text)
	-- Blizzard writes the channel as a link around "number. name - zone".
	return (text:gsub("(|Hchannel:[^|]+|h)%[%d+%. ([^%]]-)%]|h", function(link, name)
		return link .. "[" .. name:gsub("%s%-%s.*", "") .. "]|h"
	end))
end

-- Links (the sender's name, items, and addresses already linked by an earlier pattern) are set aside before each
-- pattern, so addresses inside them stay as they are.
local function linkUrls(text)
	local links = {}
	local function setAside(line)
		return (line:gsub("|H.-|h.-|h", function(link)
			links[#links + 1] = link
			return "\001" .. #links .. "\001"
		end))
	end
	for _, pattern in ipairs(URL_PATTERNS) do
		text = setAside(text):gsub(pattern, function(url)
			return ("|c%s|H%s:%s|h[%s]|h|r"):format(URL_COLOR, LINK_TYPE, url, url)
		end)
	end
	return (text:gsub("\001(%d+)\001", function(i)
		return links[tonumber(i)]
	end))
end

local function hookFrame(frame)
	local addMessage = frame.AddMessage
	frame.AddMessage = function(self, text, ...)
		if type(text) == "string" and not issecretvalue(text) then
			if ns.db.shortChannels then
				text = shortenChannels(text)
			end
			if ns.db.chatLinks then
				text = linkUrls(text)
			end
		end
		return addMessage(self, text, ...)
	end
end

StaticPopupDialogs.KSUI_COPY_URL = {
	text = "주소를 복사하세요 (Ctrl+C)",
	button1 = CLOSE,
	hasEditBox = true,
	editBoxWidth = 320,
	OnShow = function(dialog, url)
		local editBox = dialog:GetEditBox()
		editBox:SetText(url)
		editBox:HighlightText()
		editBox:SetFocus()
	end,
	EditBoxOnEscapePressed = function(editBox)
		editBox:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

function ns.InitChat()
	for i = 1, NUM_CHAT_WINDOWS do
		hookFrame(_G["ChatFrame" .. i])
	end
	LinkUtil.RegisterLinkHandler(LINK_TYPE, function(link)
		StaticPopup_Show("KSUI_COPY_URL", nil, nil, link:sub(#LINK_TYPE + 2))
	end)

	local whispers = CreateFrame("Frame")
	whispers:RegisterEvent("CHAT_MSG_WHISPER")
	whispers:RegisterEvent("CHAT_MSG_BN_WHISPER")
	whispers:SetScript("OnEvent", function()
		if ns.db.whisperSound then
			PlaySound(SOUNDKIT.TELL_MESSAGE)
		end
	end)
end
