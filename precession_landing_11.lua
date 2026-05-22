--[[
STRICT Precision Landing for QuadPlane (UPDATED LOGIC)

NEW RULES:
1) ABOVE 7m:
   - If target visible → move toward target (NO altitude hold)
   - Normal descent allowed
2) BELOW 7m:
   - STRICT precision landing
   - NO descent unless centered
   - If target lost → HOLD altitude
--]] local PARAM_TABLE_KEY = 12
local PARAM_TABLE_PREFIX = "PLND_"

local MAV_SEVERITY = {
    EMERGENCY = 0,
    ALERT = 1,
    CRITICAL = 2,
    ERROR = 3,
    WARNING = 4,
    NOTICE = 5,
    INFO = 6,
    DEBUG = 7
}

local MODE_QLAND = 20
local MODE_QLOITER = 19

local AUX_PRECLOITER = 39

local ALT_THRESHOLD = 7 -- UPDATED

local pl_started = false

local precloiter_enabled = false
local have_target = false
local last_seen_time = 0

-- ================= PARAM HELPERS =================

function bind_param(name)
    return Parameter(name)
end

function bind_add_param(name, idx, default_value)
    assert(param:add_param(PARAM_TABLE_KEY, idx, name, default_value))
    return bind_param(PARAM_TABLE_PREFIX .. name)
end

assert(param:add_table(PARAM_TABLE_KEY, PARAM_TABLE_PREFIX, 20))

-- ================= USER PARAMETERS =================

PLND_XY_GAIN = bind_add_param('XY_GAIN', 1, 2.5)
PLND_DESCENT_RADIUS = bind_add_param('DESCENT_RAD', 2, 0.35)
PLND_LOST_HOLD = bind_add_param('LOST_HOLD', 4, 1)

PLND_ENABLED = bind_param("PLND_ENABLED")

if PLND_ENABLED:get() == 0 then
    gcs:send_text(MAV_SEVERITY.INFO, "PLND: Disabled")
    return
end

-- ================= TARGET CHECK =================

local function update_target()

    if not precland:healthy() then
        return
    end

    local ok = precland:target_acquired()

    if ok then
        last_seen_time = millis()
    end

    local prev = have_target
    have_target = (millis() - last_seen_time) < 500

    if have_target ~= prev then
        gcs:send_text(have_target and MAV_SEVERITY.INFO or MAV_SEVERITY.WARNING,
            have_target and "PLND: TARGET ACQUIRED" or "PLND: TARGET LOST")
    end
end

-- ================= MODE CHECK =================

local function precision_landing_active()

    local mode = vehicle:get_mode()

    if mode == MODE_QLOITER then
        return precloiter_enabled
    end

    return quadplane:in_vtol_land_descent() or mode == MODE_QLAND
end

-- ================= PRECLOITER SWITCH =================

local function precloiter_check()

    local pos = rc:get_aux_cached(AUX_PRECLOITER)

    if pos then
        local enabled = (pos == 2)

        if enabled ~= precloiter_enabled then
            precloiter_enabled = enabled

            gcs:send_text(MAV_SEVERITY.INFO, enabled and "PLND: PRECLOITER ENABLED" or "PLND: PRECLOITER DISABLED")
        end
    end
end

-- ================= MAIN LOOP =================

local function update()

    if PLND_ENABLED:get() < 1 then
        return
    end

    precloiter_check()

    local next_WP = vehicle:get_target_location()
    if not next_WP then
        return
    end

    if not precision_landing_active() then
        return
    end

    local alt = ahrs:get_relative_position_NED_home()
    if not alt then
        return
    end

    local current_alt = -alt:z()

    update_target()

    -- ================= STATUS PRINT =================
    if not pl_started then
        if current_alt > ALT_THRESHOLD then
            gcs:send_text(MAV_SEVERITY.INFO, string.format("ALT: %.2fm | Precision Landing: NOT STARTED", current_alt))
        else
            gcs:send_text(MAV_SEVERITY.INFO, string.format("ALT: %.2fm | Precision Landing: STARTED", current_alt))
            pl_started = true
        end
    end

    -- ================= ABOVE 7m =================
    if current_alt > ALT_THRESHOLD then

        if have_target then
            local loc = precland:get_target_location()
            if loc then
                local veh_loc = ahrs:get_location()
                local gain = PLND_XY_GAIN:get()
                local new_WP = next_WP:copy()

                new_WP:lat(veh_loc:lat() + (loc:lat() - veh_loc:lat()) * gain)
                new_WP:lng(veh_loc:lng() + (loc:lng() - veh_loc:lng()) * gain)

                vehicle:update_target_location(next_WP, new_WP)
            end

            gcs:send_text(MAV_SEVERITY.INFO, string.format("ALT: %.2fm | TRACKING TARGET (>7m)", current_alt))
        end

        vehicle:set_land_descent_rate(Q_LAND_FINAL_SPD:get())
        return
    end

    -- ================= BELOW 7m → STRICT =================

    if not have_target then

        if PLND_LOST_HOLD:get() == 1 then
            vehicle:set_land_descent_rate(0)

            gcs:send_text(MAV_SEVERITY.WARNING, "PLND: HOLD ALT (TARGET LOST <7m)")
        end

        return
    end

    local loc = precland:get_target_location()
    if not loc then
        return
    end

    local veh_loc = ahrs:get_location()
    local xy_dist = veh_loc:get_distance(loc)

    -- ================= XY CORRECTION =================

    local gain = PLND_XY_GAIN:get()
    local new_WP = next_WP:copy()

    new_WP:lat(veh_loc:lat() + (loc:lat() - veh_loc:lat()) * gain)
    new_WP:lng(veh_loc:lng() + (loc:lng() - veh_loc:lng()) * gain)

    vehicle:update_target_location(next_WP, new_WP)

    -- ================= DESCENT =================

    if xy_dist <= PLND_DESCENT_RADIUS:get() then

        vehicle:set_land_descent_rate(Q_LAND_FINAL_SPD:get())

        gcs:send_text(MAV_SEVERITY.INFO, "PLND: CENTERED - DESCENT ENABLED (<7m)")

    else

        vehicle:set_land_descent_rate(0)

        gcs:send_text(MAV_SEVERITY.INFO, string.format("PLND: HOLD ALT (XY=%.2fm <7m)", xy_dist))
    end
end

-- ================= SAFE WRAPPER =================

local function protected_wrapper()

    local ok, err = pcall(update)

    if not ok then
        gcs:send_text(MAV_SEVERITY.ERROR, "PLND ERROR: " .. err)
        return protected_wrapper, 1000
    end

    return protected_wrapper, 100
end

gcs:send_text(MAV_SEVERITY.INFO, "PLND: UPDATED 7m LOGIC LOADED")

return protected_wrapper()
