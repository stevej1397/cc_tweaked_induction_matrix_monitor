-- Induction Matrix Monitor: interactive setup wizard.
--
-- Built on PixelUI v2 -- a GUI-style multi-step form for picking
-- peripherals, gate outputs, polarity, and thresholds.
--
-- Falls back to a clear error if PixelUI / shrekbox aren't installed yet
-- (run 'update' to fetch them).

local ok_pix, pixelui = pcall(require, "pixelui")
if not ok_pix then
    term.setTextColor(colors.red)
    print("pixelui is not installed. Run 'update' first to fetch it.")
    term.setTextColor(colors.white)
    return
end

local peripherals_lib = require("lib.peripherals")

-- ============================================================
-- Peripheral discovery
-- ============================================================
local function is_matrix(p)
    return type(p.getEnergy) == "function"
       and type(p.getMaxEnergy) == "function"
       and type(p.getLastInput) == "function"
       and type(p.getLastOutput) == "function"
end

local function is_monitor(p)
    return type(p.setTextScale) == "function"
       and type(p.getSize) == "function"
       and type(p.write) == "function"
end

local function find_candidates(predicate)
    local matches = {}
    for _, name in ipairs(peripheral.getNames()) do
        local ok, p = pcall(peripheral.wrap, name)
        if ok and p and predicate(p) then
            matches[#matches + 1] = name
        end
    end
    return matches
end

local function describe_matrix(name)
    local ok, p = pcall(peripheral.wrap, name)
    if not ok or not p then return "" end
    local ok2, energy = pcall(p.getEnergy)
    local ok3, max = pcall(p.getMaxEnergy)
    if ok2 and ok3 and energy and max and max > 0 then
        return string.format("  (%.1f%% full)", (energy / max) * 100)
    end
    return ""
end

local function describe_monitor(name)
    local ok, p = pcall(peripheral.wrap, name)
    if not ok or not p then return "" end
    local ok2, w, h = pcall(p.getSize)
    if ok2 and w and h then return string.format("  (%dx%d)", w, h) end
    return ""
end

-- ============================================================
-- Existing config -> defaults
-- ============================================================
local existing = {}
if fs.exists("config.lua") then
    local ok, t = pcall(dofile, shell.resolve("config.lua"))
    if ok and type(t) == "table" then existing = t end
end

local SIDES = {"top", "bottom", "left", "right", "front", "back"}
local function side_index(s)
    for i, v in ipairs(SIDES) do if v == s then return i end end
    return 1
end

local state = {
    matrices = find_candidates(is_matrix),
    monitors = find_candidates(is_monitor),
    relays = peripherals_lib.find_redstone_outputs(),

    critical = existing.critical_matrix,
    general = existing.general_matrix,
    monitor = existing.monitor,
    cg_outputs = peripherals_lib.compile_outputs(
        existing.critical_to_general_outputs or existing.critical_to_general_side),
    gs_outputs = peripherals_lib.compile_outputs(
        existing.general_to_sink_outputs or existing.general_to_sink_side),
    polarity = existing.gate_signal or "high_opens",

    critical_open_pct  = math.floor((existing.critical_open_at  or 0.75) * 100 + 0.5),
    critical_close_pct = math.floor((existing.critical_close_at or 0.70) * 100 + 0.5),
    general_open_pct   = math.floor((existing.general_open_at   or 0.90) * 100 + 0.5),
    general_close_pct  = math.floor((existing.general_close_at  or 0.85) * 100 + 0.5),

    cancelled = false,
    saved = false,
}

-- "computer" is always available; relays come after
local function peripheral_choices()
    local list = {"computer"}
    for _, name in ipairs(state.relays) do list[#list + 1] = name end
    return list
end

-- ============================================================
-- App + layout
-- ============================================================
local app = pixelui.create({background = colors.gray})
local root = app:getRoot()
local SW, SH = app.window.getSize()

-- Helper: PixelUI Labels default to width=1 (which wraps text vertically),
-- so always pass an explicit width. wrap=false keeps single-line.
local function mkLabel(opts)
    opts.width = opts.width or (SW - opts.x - 1)
    opts.height = opts.height or 1
    if opts.wrap == nil then opts.wrap = false end
    return app:createLabel(opts)
end

-- Title bar (row 1)
root:addChild(mkLabel({
    x = 2, y = 1, text = "Induction Matrix Monitor - Setup",
    fg = colors.white, bg = colors.gray,
}))

-- Step indicator (row 2)
local stepLabel = mkLabel({
    x = 2, y = 2, text = "",
    fg = colors.lightGray, bg = colors.gray,
})
root:addChild(stepLabel)

-- Content frame area (rows 3..SH-2). Each step's Frame lives here.
local CONTENT_X, CONTENT_Y = 1, 3
local CONTENT_W, CONTENT_H = SW, SH - 4

local STEP_NAMES = {
    "Critical matrix",
    "General matrix",
    "Monitor",
    "Critical -> General outputs",
    "General -> Sink outputs",
    "Polarity & thresholds",
    "Confirm & save",
}
local NUM_STEPS = #STEP_NAMES

local function newStepFrame()
    local f = app:createFrame({
        x = CONTENT_X, y = CONTENT_Y,
        width = CONTENT_W, height = CONTENT_H,
        bg = colors.black, fg = colors.white,
    })
    f.visible = false
    root:addChild(f)
    return f
end

-- Status / error label (row SH-1)
local statusLabel = mkLabel({
    x = 2, y = SH - 1, text = "",
    fg = colors.yellow, bg = colors.gray,
})
root:addChild(statusLabel)

local function setStatus(msg, color)
    statusLabel:setText(msg or "")
    if statusLabel.fg ~= nil then statusLabel.fg = color or colors.yellow end
end

-- ============================================================
-- Step 1, 2, 3: peripheral pickers (ComboBox + info)
-- ============================================================
local function buildPeripheralStep(opts)
    local frame = newStepFrame()
    local INNER_W = CONTENT_W - 4
    frame:addChild(mkLabel({
        x = 2, y = 1, width = INNER_W, text = opts.title,
        fg = colors.cyan, bg = colors.black,
    }))
    frame:addChild(mkLabel({
        x = 2, y = 2, width = INNER_W, text = opts.help or "",
        fg = colors.lightGray, bg = colors.black,
    }))

    local items = {}
    for _, name in ipairs(opts.candidates) do items[#items + 1] = name end
    if #items == 0 then
        frame:addChild(mkLabel({
            x = 2, y = 5, width = INNER_W,
            text = "(no candidates detected -- check wiring)",
            fg = colors.red, bg = colors.black,
        }))
        return frame, function() return nil end
    end

    local infoLabel = mkLabel({
        x = 2, y = 7, width = INNER_W, text = "",
        fg = colors.lightGray, bg = colors.black,
    })

    -- Pick a sensible starting index
    local startIdx = 1
    if opts.initial then
        for i, n in ipairs(opts.candidates) do
            if n == opts.initial then startIdx = i; break end
        end
    end

    local cb = app:createComboBox({
        x = 2, y = 5, width = CONTENT_W - 4,
        items = items,
        selectedIndex = startIdx,
        bg = colors.gray, fg = colors.white,
        dropdownBg = colors.gray, dropdownFg = colors.white,
        highlightBg = colors.lime, highlightFg = colors.black,
        onChange = function(self, index)
            local name = opts.candidates[index]
            opts.onPick(name)
            infoLabel:setText(opts.describer and (name .. opts.describer(name)) or name)
        end,
    })
    frame:addChild(cb)
    frame:addChild(infoLabel)

    -- Apply initial pick
    local picked = opts.candidates[startIdx]
    opts.onPick(picked)
    infoLabel:setText(opts.describer and (picked .. opts.describer(picked)) or picked)

    return frame, function() return cb:getSelectedItem() end
end

local step1 = buildPeripheralStep({
    title = "Step 1/" .. NUM_STEPS .. ": Pick the CRITICAL matrix",
    help = "The matrix that should always stay charged (drives the others).",
    candidates = state.matrices,
    initial = state.critical,
    describer = describe_matrix,
    onPick = function(name) state.critical = name end,
})

local step2 = buildPeripheralStep({
    title = "Step 2/" .. NUM_STEPS .. ": Pick the GENERAL matrix",
    help = "The matrix that fills only after the critical one is at threshold.",
    candidates = state.matrices,
    initial = state.general,
    describer = describe_matrix,
    onPick = function(name) state.general = name end,
})

local step3 = buildPeripheralStep({
    title = "Step 3/" .. NUM_STEPS .. ": Pick the MONITOR",
    help = "4x3 advanced monitor recommended (~60x30 chars at scale 0.5).",
    candidates = state.monitors,
    initial = state.monitor,
    describer = describe_monitor,
    onPick = function(name) state.monitor = name end,
})

-- ============================================================
-- Step 4, 5: output list editors
-- ============================================================
local function buildOutputsStep(stepIdx, title, list_ref)
    local frame = newStepFrame()
    local INNER_W = CONTENT_W - 4

    frame:addChild(mkLabel({
        x = 2, y = 1, width = INNER_W,
        text = string.format("Step %d/%d: %s", stepIdx, NUM_STEPS, title),
        fg = colors.cyan, bg = colors.black,
    }))
    frame:addChild(mkLabel({
        x = 2, y = 2, width = INNER_W,
        text = "Computer emits redstone on every output when gate is OPEN.",
        fg = colors.lightGray, bg = colors.black,
    }))

    -- The output list. Rebuilt whenever the data changes.
    local outputList
    local function format_item(o) return string.format("%s side=%s", o.peripheral, o.side) end
    local function refresh()
        local items = {}
        for _, o in ipairs(list_ref()) do items[#items + 1] = format_item(o) end
        if #items == 0 then items = {"(no outputs -- gate disabled)"} end
        outputList:setItems(items)
    end

    outputList = app:createList({
        x = 2, y = 4, width = CONTENT_W - 4, height = 5,
        items = {},
        bg = colors.gray, fg = colors.white,
        highlightBg = colors.lime, highlightFg = colors.black,
    })
    frame:addChild(outputList)

    -- "Add output" row
    frame:addChild(mkLabel({
        x = 2, y = 10, width = 4, text = "Add:",
        fg = colors.lightGray, bg = colors.black,
    }))

    local periphCb = app:createComboBox({
        x = 7, y = 10, width = 22,
        items = peripheral_choices(),
        selectedIndex = 1,
        bg = colors.gray, fg = colors.white,
    })
    frame:addChild(periphCb)

    local sideCb = app:createComboBox({
        x = 30, y = 10, width = 10,
        items = SIDES,
        selectedIndex = 1,
        bg = colors.gray, fg = colors.white,
    })
    frame:addChild(sideCb)

    local addBtn = app:createButton({
        x = 41, y = 10, width = CONTENT_W - 42, height = 1,
        label = "+ Add", bg = colors.green, fg = colors.white,
        onClick = function()
            local periph = periphCb:getSelectedItem()
            local side = sideCb:getSelectedItem()
            if periph and side then
                table.insert(list_ref(), {peripheral = periph, side = side})
                refresh()
                setStatus("added " .. periph .. " side=" .. side, colors.lime)
            end
        end,
    })
    frame:addChild(addBtn)

    local removeBtn = app:createButton({
        x = 2, y = 12, width = CONTENT_W - 4, height = 1,
        label = "- Remove selected", bg = colors.red, fg = colors.white,
        onClick = function()
            local list = list_ref()
            local idx = outputList.selectedIndex
            if idx and list[idx] then
                local removed = table.remove(list, idx)
                refresh()
                setStatus("removed " .. removed.peripheral .. " side=" .. removed.side, colors.lime)
            else
                setStatus("nothing selected to remove", colors.yellow)
            end
        end,
    })
    frame:addChild(removeBtn)

    refresh()
    return frame
end

local step4 = buildOutputsStep(4, "Critical -> General gate outputs",
    function() return state.cg_outputs end)
local step5 = buildOutputsStep(5, "General -> Sink gate outputs",
    function() return state.gs_outputs end)

-- ============================================================
-- Step 6: polarity + thresholds
-- ============================================================
local step6 = newStepFrame()
local STEP6_W = CONTENT_W - 4
step6:addChild(mkLabel({
    x = 2, y = 1, width = STEP6_W,
    text = "Step 6/" .. NUM_STEPS .. ": Polarity & thresholds",
    fg = colors.cyan, bg = colors.black,
}))

step6:addChild(mkLabel({
    x = 2, y = 3, width = STEP6_W, text = "Redstone polarity:",
    fg = colors.white, bg = colors.black,
}))
local radioHigh = app:createRadioButton({
    x = 4, y = 4, label = "High opens (recommended)",
    group = "polarity", value = "high_opens",
    selected = state.polarity == "high_opens",
    fg = colors.white, bg = colors.black,
    onChange = function(self, selected)
        if selected then state.polarity = "high_opens" end
    end,
})
local radioLow = app:createRadioButton({
    x = 4, y = 5, label = "Low opens",
    group = "polarity", value = "low_opens",
    selected = state.polarity == "low_opens",
    fg = colors.white, bg = colors.black,
    onChange = function(self, selected)
        if selected then state.polarity = "low_opens" end
    end,
})
step6:addChild(radioHigh)
step6:addChild(radioLow)

step6:addChild(mkLabel({
    x = 2, y = 7, width = STEP6_W, text = "Gate thresholds (open / close):",
    fg = colors.white, bg = colors.black,
}))

local function thresholdRow(y, label, getter, setter)
    step6:addChild(mkLabel({
        x = 2, y = y, width = 14, text = label,
        fg = colors.lightGray, bg = colors.black,
    }))
    local slider = app:createSlider({
        x = 16, y = y, width = CONTENT_W - 22,
        min = 1, max = 99, step = 1, value = getter(),
        showValue = true,
        bg = colors.gray, fg = colors.white,
        formatValue = function(self, v) return string.format("%d%%", v) end,
        onChange = function(self, v) setter(v) end,
    })
    step6:addChild(slider)
end

thresholdRow(8,  "critical open:",  function() return state.critical_open_pct end,
    function(v) state.critical_open_pct = v end)
thresholdRow(9,  "critical close:", function() return state.critical_close_pct end,
    function(v) state.critical_close_pct = v end)
thresholdRow(10, "general open:",   function() return state.general_open_pct end,
    function(v) state.general_open_pct = v end)
thresholdRow(11, "general close:",  function() return state.general_close_pct end,
    function(v) state.general_close_pct = v end)

step6:addChild(mkLabel({
    x = 2, y = 13, width = STEP6_W,
    text = "(close must be <= open for each gate)",
    fg = colors.gray, bg = colors.black,
}))

-- ============================================================
-- Step 7: confirm & save
-- ============================================================
local step7 = newStepFrame()
local STEP7_W = CONTENT_W - 4
step7:addChild(mkLabel({
    x = 2, y = 1, width = STEP7_W,
    text = "Step 7/" .. NUM_STEPS .. ": Confirm & save",
    fg = colors.cyan, bg = colors.black,
}))

local summaryLabels = {}
for i = 1, 12 do
    local l = mkLabel({
        x = 2, y = 2 + i, width = STEP7_W, text = "",
        fg = colors.white, bg = colors.black,
    })
    step7:addChild(l)
    summaryLabels[i] = l
end

local function summarize_outputs(outputs)
    if #outputs == 0 then return "(disabled)" end
    local parts = {}
    for _, o in ipairs(outputs) do
        parts[#parts + 1] = o.peripheral .. ":" .. o.side
    end
    return table.concat(parts, ", ")
end

local function refreshSummary()
    summaryLabels[1]:setText("Critical matrix : " .. tostring(state.critical))
    summaryLabels[2]:setText("General  matrix : " .. tostring(state.general))
    summaryLabels[3]:setText("Monitor         : " .. tostring(state.monitor))
    summaryLabels[4]:setText("C->G outputs    : " .. summarize_outputs(state.cg_outputs))
    summaryLabels[5]:setText("G->S outputs    : " .. summarize_outputs(state.gs_outputs))
    summaryLabels[6]:setText("Polarity        : " .. state.polarity)
    summaryLabels[7]:setText(string.format("Critical gate   : open >= %d%%, close <= %d%%",
        state.critical_open_pct, state.critical_close_pct))
    summaryLabels[8]:setText(string.format("General gate    : open >= %d%%, close <= %d%%",
        state.general_open_pct, state.general_close_pct))
    summaryLabels[9]:setText("")
    summaryLabels[10]:setText("Click Save to write config.lua and exit.")
    summaryLabels[11]:setText("(existing config.lua will be backed up to config.lua.bak)")
end

-- ============================================================
-- Step registry + navigation
-- ============================================================
local steps = {step1, step2, step3, step4, step5, step6, step7}
local currentStep = 1

local function validateStep(n)
    if n == 1 and not state.critical then return "Pick a critical matrix" end
    if n == 2 then
        if not state.general then return "Pick a general matrix" end
        if state.general == state.critical then return "General and critical must be different matrices" end
    end
    if n == 3 and not state.monitor then return "Pick a monitor" end
    if n == 6 then
        if state.critical_close_pct > state.critical_open_pct then
            return "Critical close must be <= critical open"
        end
        if state.general_close_pct > state.general_open_pct then
            return "General close must be <= general open"
        end
    end
    return nil
end

local backBtn, nextBtn, cancelBtn

local function gotoStep(n)
    for i, frame in ipairs(steps) do frame.visible = (i == n) end
    currentStep = n
    stepLabel:setText(string.format("Step %d / %d  -  %s", n, NUM_STEPS, STEP_NAMES[n]))
    backBtn.disabled = (n == 1)
    if n == NUM_STEPS then
        nextBtn:setLabel("Save")
        refreshSummary()
    else
        nextBtn:setLabel("Next >")
    end
    setStatus("")
end

-- ============================================================
-- Bottom navigation buttons (row SH)
-- ============================================================
backBtn = app:createButton({
    x = 2, y = SH, width = 8, height = 1,
    label = "< Back", bg = colors.gray, fg = colors.white,
    onClick = function()
        if currentStep > 1 then gotoStep(currentStep - 1) end
    end,
})
root:addChild(backBtn)

cancelBtn = app:createButton({
    x = 12, y = SH, width = 10, height = 1,
    label = "Cancel", bg = colors.red, fg = colors.white,
    onClick = function()
        state.cancelled = true
        app:stop()
    end,
})
root:addChild(cancelBtn)

nextBtn = app:createButton({
    x = SW - 9, y = SH, width = 9, height = 1,
    label = "Next >", bg = colors.lime, fg = colors.black,
    onClick = function()
        local err = validateStep(currentStep)
        if err then setStatus(err, colors.red); return end
        if currentStep < NUM_STEPS then
            gotoStep(currentStep + 1)
        else
            state.saved = true
            app:stop()
        end
    end,
})
root:addChild(nextBtn)

gotoStep(1)

-- ============================================================
-- Run with our own loop so we could inject timers later
-- ============================================================
app.running = true
app:render()
local ok, err = pcall(function()
    while app.running do
        local event = {os.pullEvent()}
        if event[1] == "terminate" then
            app.running = false
            state.cancelled = true
        else
            app:step(table.unpack(event))
        end
    end
end)

-- Restore terminal
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)

if not ok then
    term.setTextColor(colors.red)
    print("Setup wizard crashed:")
    print(tostring(err))
    term.setTextColor(colors.white)
    return
end

if state.cancelled or not state.saved then
    print("Setup cancelled. config.lua not modified.")
    return
end

-- ============================================================
-- Write config.lua
-- ============================================================
local function fmt_str(s)
    if s == nil then return "nil" end
    return string.format("%q", s)
end

local function fmt_outputs(outputs)
    if not outputs or #outputs == 0 then return "{}" end
    local lines = {"{"}
    for _, o in ipairs(outputs) do
        lines[#lines + 1] = string.format(
            "        {peripheral = %q, side = %q},",
            o.peripheral or "computer", o.side)
    end
    lines[#lines + 1] = "    }"
    return table.concat(lines, "\n")
end

local config_text = string.format([[
-- ============================================================
-- Induction Matrix Monitor configuration
-- Generated by setup. Re-run 'setup' anytime to regenerate.
-- ============================================================
return {
    critical_matrix = %s,
    general_matrix  = %s,
    monitor         = %s,

    critical_to_general_outputs = %s,
    general_to_sink_outputs     = %s,

    gate_signal = %s,

    critical_open_at  = %s,
    critical_close_at = %s,
    general_open_at   = %s,
    general_close_at  = %s,

    live_interval        = %s,
    history_interval     = %s,
    history_max_samples  = %s,
    history_path         = "/history.dat",

    text_scale     = %s,
    critical_color = colors.lime,
    general_color  = colors.cyan,
}
]],
    fmt_str(state.critical),
    fmt_str(state.general),
    fmt_str(state.monitor),
    fmt_outputs(state.cg_outputs),
    fmt_outputs(state.gs_outputs),
    fmt_str(state.polarity),
    state.critical_open_pct / 100,
    state.critical_close_pct / 100,
    state.general_open_pct / 100,
    state.general_close_pct / 100,
    existing.live_interval or 2,
    existing.history_interval or 30,
    existing.history_max_samples or 1440,
    existing.text_scale or 0.5
)

if fs.exists("config.lua") then
    if fs.exists("config.lua.bak") then fs.delete("config.lua.bak") end
    fs.copy("config.lua", "config.lua.bak")
    print("backed up previous config to config.lua.bak")
end

local f = fs.open("config.lua", "w")
f.write(config_text)
f.close()

term.setTextColor(colors.lime)
print("config.lua written.")
term.setTextColor(colors.white)
print("Run 'check' to verify, then reboot (or 'monitor') to start.")
