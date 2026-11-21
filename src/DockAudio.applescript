-- DockAudio - background applet
--
-- Every few seconds this asks the bundled `dockaudio` script what to do.
-- The script does all the deciding (is the dock plugged in? which speaker?);
-- this applet only does what a script cannot: it opens the macOS Sound menu
-- and clicks a speaker in it, exactly as you would by hand.
--
-- It is an applet (rather than a plain script) so that macOS has a named app,
-- "DockAudio", to grant the Accessibility permission to.

property baseWin : 0

on run
	set baseWin to 0
	try
		my helperCmd("app-started")
	end try
end run

on idle
	try
		my tick()
	on error errMsg number errNum
		try
			my helperCmd("log " & quoted form of ("applet error " & errNum & ": " & errMsg))
		end try
	end try
	return 3
end idle

-- ---------------------------------------------------------------------------
-- talking to the helper script
-- ---------------------------------------------------------------------------

on helperCmd(args)
	set appPath to POSIX path of (path to me)
	if appPath does not end with "/" then set appPath to appPath & "/"
	set helperPath to appPath & "Contents/Resources/dockaudio"
	return do shell script "/bin/bash " & quoted form of helperPath & " " & args
end helperCmd

on tick()
	set tickReply to my helperCmd("tick")
	if tickReply is "" or tickReply is "none" then return
	set parts to my splitText(tickReply, tab)
	set act to my nth(parts, 1)
	set reqId to my nth(parts, 2)
	if act is "switch" then
		set res to my switchTo(my nth(parts, 3), my nth(parts, 4))
		if reqId is "auto" and res starts with ("fail" & tab & "NO_") then
			try
				display notification "Open Terminal and run: dockaudio setup" with title "DockAudio can't switch speakers"
			end try
		end if
	else if act is "list" then
		set res to my listDevices()
	else if act is "dump" then
		set res to my dumpUI()
	else if act is "check" then
		set res to my checkAccess()
	else if act is "quit" then
		my helperCmd("result " & quoted form of reqId & " " & quoted form of ("ok" & tab & "bye"))
		tell me to quit
		return
	else
		set res to "fail" & tab & "unknown action " & act
	end if
	my helperCmd("result " & quoted form of reqId & " " & quoted form of res)
end tick

on splitText(theText, theDelim)
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to theDelim
	set theParts to text items of theText
	set AppleScript's text item delimiters to oldDelims
	return theParts
end splitText

on nth(theList, n)
	if (count of theList) < n then return ""
	return (item n of theList) as text
end nth

-- ---------------------------------------------------------------------------
-- reading the screen
-- ---------------------------------------------------------------------------

-- An accessibility attribute as text, or "" if it is missing.
on axAttr(el, attrName)
	try
		tell application "System Events" to set v to value of attribute attrName of el
		if v is missing value then return ""
		return v as text
	on error
		return ""
	end try
end axAttr

on describe(el)
	return (my axAttr(el, "AXRole")) & " | " & (my axAttr(el, "AXSubrole")) & " | " & (my axAttr(el, "AXTitle")) & " | " & (my axAttr(el, "AXDescription")) & " | " & (my axAttr(el, "AXIdentifier")) & " | " & (my axAttr(el, "AXValue"))
end describe

-- "" when the Sound menu can be scripted, otherwise the reason it cannot.
on accessProblem()
	try
		tell application "System Events"
			set proc to first application process whose bundle identifier is "com.apple.controlcenter"
		end tell
	on error errMsg number errNum
		if errNum is -1743 then return "NO_AUTOMATION"
		return "Control Center is not running yet (" & errNum & ")"
	end try
	try
		tell application "System Events"
			set barCount to count of menu bars of proc
		end tell
		return ""
	on error errMsg number errNum
		if errNum is -1743 then return "NO_AUTOMATION"
		set isTrusted to true
		try
			tell application "System Events" to set isTrusted to UI elements enabled
		end try
		if (not isTrusted) or errMsg contains "assistive" or errMsg contains "not allowed" then return "NO_ACCESSIBILITY"
		return "System Events error " & errNum & ": " & errMsg
	end try
end accessProblem

on checkAccess()
	set problem to my accessProblem()
	if problem is not "" then return "fail" & tab & problem
	try
		set soundItem to my findSoundItem()
	on error errMsg
		return "fail" & tab & errMsg
	end try
	if soundItem is missing value then return "fail" & tab & "NO_SOUND_ICON"
	return "ok" & tab & "ready"
end checkAccess

-- The Sound icon in the menu bar, or missing value.
on findSoundItem()
	set fallbackItem to missing value
	tell application "System Events"
		set proc to first application process whose bundle identifier is "com.apple.controlcenter"
		set barList to menu bars of proc
	end tell
	repeat with mb in barList
		set theBar to contents of mb
		tell application "System Events" to set itemList to menu bar items of theBar
		repeat with mbi in itemList
			set theItem to contents of mbi
			set itemIdent to my axAttr(theItem, "AXIdentifier")
			if itemIdent is "com.apple.menuextra.sound" then return theItem
			if fallbackItem is missing value then
				if itemIdent contains "sound" then
					set fallbackItem to theItem
				else
					set itemDesc to my axAttr(theItem, "AXDescription")
					set itemTitle to my axAttr(theItem, "AXTitle")
					if itemDesc starts with "Sound" or itemTitle starts with "Sound" then set fallbackItem to theItem
				end if
			end if
		end repeat
	end repeat
	return fallbackItem
end findSoundItem

on ccWindowCount()
	tell application "System Events"
		set proc to first application process whose bundle identifier is "com.apple.controlcenter"
		return count of windows of proc
	end tell
end ccWindowCount

on panelIsOpen()
	try
		return (my ccWindowCount()) > baseWin
	on error
		return false
	end try
end panelIsOpen

on waitForPanel(secs)
	repeat (secs * 5) times
		if my panelIsOpen() then return true
		delay 0.2
	end repeat
	return false
end waitForPanel

on openSoundPanel()
	set soundItem to my findSoundItem()
	if soundItem is missing value then error "NO_SOUND_ICON"
	set baseWin to my ccWindowCount()
	try
		tell application "System Events" to click soundItem
	end try
	if my waitForPanel(3) then return
	-- some macOS versions want an explicit press instead of a click
	try
		tell application "System Events" to perform action "AXPress" of soundItem
	end try
	if my waitForPanel(3) then return
	if (count of (my collectDevices())) > 0 then
		set baseWin to (my ccWindowCount()) - 1
		return
	end if
	error "PANEL_DID_NOT_OPEN: clicked the Sound icon but its panel did not appear"
end openSoundPanel

on closeSoundPanel()
	try
		if not (my panelIsOpen()) then return
		set soundItem to my findSoundItem()
		if soundItem is not missing value then
			tell application "System Events" to click soundItem
		end if
	end try
end closeSoundPanel

-- Every output device shown in the open Sound panel, as a list of
-- {label, identifier, value, element}. value is "1" for the selected device.
on collectDevices()
	set devs to {}
	set others to {}
	try
		tell application "System Events"
			set proc to first application process whose bundle identifier is "com.apple.controlcenter"
			set winList to windows of proc
		end tell
		repeat with w in winList
			set theWin to contents of w
			set els to {}
			try
				tell application "System Events" to set els to entire contents of theWin
			end try
			repeat with e in els
				set el to contents of e
				set elRole to my axAttr(el, "AXRole")
				set elIdent to my axAttr(el, "AXIdentifier")
				if elRole is "AXCheckBox" then
					set end of devs to {my labelFor(el, elIdent), elIdent, my axAttr(el, "AXValue"), el}
				else if elIdent contains "sound-device" then
					set end of others to {my labelFor(el, elIdent), elIdent, my axAttr(el, "AXValue"), el}
				end if
			end repeat
		end repeat
	end try
	if (count of devs) is 0 then return others
	return devs
end collectDevices

-- The name a person would recognise the device by.
on labelFor(el, elIdent)
	set lbl to my axAttr(el, "AXTitle")
	if lbl is "" then set lbl to my axAttr(el, "AXDescription")
	if lbl is "" then
		try
			tell application "System Events" to set v to value of static text 1 of el
			if v is not missing value then set lbl to v as text
		end try
	end if
	if lbl is "" then
		set lbl to elIdent
		set marker to "sound-device-"
		try
			if lbl contains marker then set lbl to text ((offset of marker in lbl) + (length of marker)) thru -1 of lbl
		end try
	end if
	return lbl
end labelFor

on matchDevice(devs, targetName, targetIdent)
	if targetName is "" and targetIdent is "" then return missing value
	if targetName is not "" then
		repeat with d in devs
			set dev to contents of d
			if (item 1 of dev) is targetName then return dev
		end repeat
	end if
	if targetIdent is not "" then
		repeat with d in devs
			set dev to contents of d
			if (item 2 of dev) is targetIdent then return dev
		end repeat
	end if
	if targetName is "" then return missing value
	repeat with d in devs
		set dev to contents of d
		if (item 2 of dev) ends with targetName then return dev
	end repeat
	repeat with d in devs
		set dev to contents of d
		if (item 1 of dev) contains targetName or (item 2 of dev) contains targetName then return dev
	end repeat
	return missing value
end matchDevice

on isOn(v)
	return (v is "1" or v is "true")
end isOn

on labelsOf(devs)
	set txt to ""
	repeat with d in devs
		set dev to contents of d
		if txt is not "" then set txt to txt & ", "
		set txt to txt & (item 1 of dev)
	end repeat
	if txt is "" then return "nothing"
	return txt
end labelsOf

-- ---------------------------------------------------------------------------
-- actions
-- ---------------------------------------------------------------------------

-- Returns "ok<TAB>...", "clicked<TAB>..." (clicked, not confirmed) or "fail<TAB>...".
on switchTo(targetName, targetIdent)
	set problem to my accessProblem()
	if problem is not "" then return "fail" & tab & problem
	try
		my openSoundPanel()
	on error errMsg
		my closeSoundPanel()
		return "fail" & tab & errMsg
	end try

	-- AirPlay speakers take a moment to show up after the panel opens
	set devs to {}
	set hit to missing value
	repeat 9 times
		set devs to my collectDevices()
		set hit to my matchDevice(devs, targetName, targetIdent)
		if hit is not missing value then exit repeat
		delay 1
	end repeat
	if hit is missing value then
		set seen to my labelsOf(devs)
		my closeSoundPanel()
		return "fail" & tab & "NOT_FOUND: '" & targetName & "' is not in the Sound menu right now (it shows: " & seen & ")"
	end if

	if my isOn(item 3 of hit) then
		my closeSoundPanel()
		return "ok" & tab & "already selected"
	end if

	set theTarget to item 4 of hit
	try
		tell application "System Events" to click theTarget
	on error
		try
			tell application "System Events" to perform action "AXPress" of theTarget
		on error errMsg
			my closeSoundPanel()
			return "fail" & tab & "could not click the speaker: " & errMsg
		end try
	end try

	set verified to false
	repeat 8 times
		delay 1
		if not (my panelIsOpen()) then exit repeat
		set hit to my matchDevice(my collectDevices(), targetName, targetIdent)
		if hit is not missing value then
			if my isOn(item 3 of hit) then
				set verified to true
				exit repeat
			end if
		end if
	end repeat
	my closeSoundPanel()
	if verified then return "ok" & tab & "selected in the Sound menu"
	return "clicked" & tab & "clicked, not confirmed"
end switchTo

-- "ok<TAB>count" followed by one "label<TAB>identifier<TAB>value" line each.
on listDevices()
	set problem to my accessProblem()
	if problem is not "" then return "fail" & tab & problem
	try
		my openSoundPanel()
	on error errMsg
		my closeSoundPanel()
		return "fail" & tab & errMsg
	end try
	delay 4
	set devs to my collectDevices()
	my closeSoundPanel()
	set txt to "ok" & tab & (count of devs)
	repeat with d in devs
		set dev to contents of d
		set txt to txt & linefeed & (item 1 of dev) & tab & (item 2 of dev) & tab & (item 3 of dev)
	end repeat
	return txt
end listDevices

-- A plain-text description of the menu bar and the Sound panel, used to adapt
-- DockAudio when a macOS update rearranges things.
on dumpUI()
	set problem to my accessProblem()
	if problem is not "" then return "fail" & tab & problem
	set txt to "ok" & tab & "dump"
	set txt to txt & linefeed & "columns: role | subrole | title | description | identifier | value"
	try
		tell application "System Events"
			set proc to first application process whose bundle identifier is "com.apple.controlcenter"
			set barList to menu bars of proc
		end tell
		repeat with mb in barList
			set theBar to contents of mb
			tell application "System Events" to set itemList to menu bar items of theBar
			repeat with mbi in itemList
				set txt to txt & linefeed & "menubar: " & my describe(contents of mbi)
			end repeat
		end repeat
	on error errMsg
		set txt to txt & linefeed & "menubar error: " & errMsg
	end try

	set soundItem to missing value
	try
		set soundItem to my findSoundItem()
	end try
	if soundItem is missing value then return txt & linefeed & "sound icon: NOT FOUND"
	set txt to txt & linefeed & "sound icon: " & my describe(soundItem)

	set winBefore to my ccWindowCount()
	try
		tell application "System Events" to click soundItem
	on error errMsg
		set txt to txt & linefeed & "click error: " & errMsg
	end try
	delay 4
	set winAfter to my ccWindowCount()
	set txt to txt & linefeed & "windows before click: " & winBefore & ", after: " & winAfter
	try
		tell application "System Events"
			set proc to first application process whose bundle identifier is "com.apple.controlcenter"
			set winList to windows of proc
		end tell
		set winIndex to 0
		repeat with w in winList
			set theWin to contents of w
			set winIndex to winIndex + 1
			set txt to txt & linefeed & "window " & winIndex & ": " & my describe(theWin)
			set els to {}
			tell application "System Events" to set els to entire contents of theWin
			repeat with e in els
				set txt to txt & linefeed & "  w" & winIndex & ": " & my describe(contents of e)
			end repeat
		end repeat
	on error errMsg
		set txt to txt & linefeed & "window error: " & errMsg
	end try
	if winAfter > winBefore then
		try
			tell application "System Events" to click soundItem
		end try
	end if
	return txt
end dumpUI
