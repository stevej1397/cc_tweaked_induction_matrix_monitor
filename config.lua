-- ============================================================
-- Induction Matrix Monitor configuration
-- Edit the values below to match your wiring, then reboot.
-- ============================================================
return {
    -- ---- Peripheral names ----
    -- Use `peripherals` at a shell prompt to list connected peripherals.
    -- These are the network names assigned by wired modems.
    critical_matrix = "inductionPort_0",
    general_matrix  = "inductionPort_1",
    monitor         = "monitor_0",

    -- ---- Redstone gate sides ----
    -- Sides on the computer block where the redstone signal is emitted.
    -- Valid values: "top", "bottom", "left", "right", "front", "back".
    -- Set to nil to disable that gate (e.g. for testing).
    critical_to_general_side = "left",
    general_to_sink_side     = "right",

    -- ---- Gate polarity ----
    -- "high_opens": redstone signal HIGH = gate open (recommended; failsafe)
    -- "low_opens":  redstone signal LOW  = gate open
    -- Wire Mekanism cables with Configurator -> Redstone mode = High.
    gate_signal = "high_opens",

    -- ---- Gate thresholds (fraction 0..1) ----
    -- A gate opens when fill >= open_at and closes when fill <= close_at.
    -- The gap between them is hysteresis to prevent rapid flapping.
    critical_open_at  = 0.75,
    critical_close_at = 0.70,
    general_open_at   = 0.90,
    general_close_at  = 0.85,

    -- ---- Sampling ----
    live_interval        = 2,    -- seconds between live readouts and redstone updates
    history_interval     = 30,   -- seconds between history samples
    history_max_samples  = 1440, -- 1440 * 30s = 12h
    history_path         = "/history.dat",

    -- ---- Display ----
    text_scale     = 0.5,
    critical_color = colors.lime,
    general_color  = colors.cyan,
}
