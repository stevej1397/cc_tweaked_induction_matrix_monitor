-- ============================================================
-- Induction Matrix Monitor configuration (defaults).
-- Run 'setup' to generate this interactively, or edit by hand.
-- ============================================================
return {
    -- ---- Peripheral names ----
    -- Run `peripherals` at a shell prompt to list connected names.
    critical_matrix = "inductionPort_0",
    general_matrix  = "inductionPort_1",
    monitor         = "monitor_0",

    -- ---- Redstone outputs ----
    -- Each gate is a *list* of outputs. Every entry receives the redstone
    -- signal when the gate should be OPEN.  Mix and match the computer
    -- itself with any number of Redstone Relay sides.
    --
    --   peripheral = "computer"          -> uses redstone.setOutput(side, ...)
    --   peripheral = "redstone_relay"    -> calls setOutput on that relay
    --
    -- Set to {} to disable a gate.
    critical_to_general_outputs = {
        {peripheral = "computer", side = "left"},
    },
    general_to_sps_outputs = {
        {peripheral = "computer", side = "front"},
    },
    general_to_sink_outputs = {
        {peripheral = "computer", side = "right"},
    },

    -- ---- Gate polarity ----
    -- "high_opens": redstone HIGH = gate open (recommended; failsafe)
    -- "low_opens" : redstone LOW  = gate open
    -- Pair with Mekanism cable Configurator -> Redstone mode = High (or Low).
    gate_signal = "high_opens",

    -- ---- Gate thresholds (fractions 0..1) ----
    -- Opens when fill >= open_at, closes when fill <= close_at.
    -- SPS gate uses lower thresholds than the sink so it gets first claim
    -- on overflow power once the critical matrix is full.
    critical_open_at      = 0.75,
    critical_close_at     = 0.70,
    general_sps_open_at   = 0.55,
    general_sps_close_at  = 0.50,
    general_open_at       = 0.95,
    general_close_at      = 0.90,

    -- ---- Sampling ----
    live_interval        = 2,    -- seconds between live readouts + gate updates
    history_interval     = 30,   -- seconds between persisted history samples
    history_max_samples  = 1440, -- 1440 * 30s = 12h
    history_path         = "/history.dat",

    -- ---- Display ----
    text_scale     = 0.5,
    critical_color = colors.lime,
    general_color  = colors.cyan,

    -- Power unit shown on the monitor. One of: "J", "FE", "RF", "EU".
    -- (Mekanism stores power in Joules natively; the others use Mekanism's
    -- default conversion ratios -- 1 FE/RF = 2.5 J, 1 EU = 25 J.)
    energy_unit    = "J",

    -- Rate period:
    --   "s" - per second (e.g. "1.14 GFE/s") -- multiplies Mekanism's
    --         per-tick value by 20.
    --   "t" - per tick   (e.g. "57.1 MFE/t") -- matches the in-game
    --         Induction Matrix Port GUI exactly.
    rate_period    = "s",
}
