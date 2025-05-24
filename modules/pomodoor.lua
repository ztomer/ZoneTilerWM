--- Pomodoro module
--------------------------------------------------------------------------------
local config = require "config"

local pom = {}
pom.bar = {
    indicator_height = config.pomodoro.indicator_height,
    indicator_alpha = config.pomodoro.indicator_alpha,
    indicator_in_all_spaces = config.pomodoro.indicator_in_all_spaces,
    color_time_remaining = config.pomodoro.color_time_remaining,
    color_time_used = config.pomodoro.color_time_used,

    c_left = hs.drawing.rectangle(hs.geometry.rect(0, 0, 0, 0)),
    c_used = hs.drawing.rectangle(hs.geometry.rect(0, 0, 0, 0))
}

pom.config = {
    enable_color_bar = config.pomodoro.enable_color_bar,
    work_period_sec = config.pomodoro.work_period_sec,
    rest_period_sec = config.pomodoro.rest_period_sec
}

pom.var = {
    is_active = false,
    disable_count = 0,
    work_count = 0,
    curr_active_type = "work", -- {"work", "rest"}
    time_left = pom.config.work_period_sec,
    max_time_sec = pom.config.work_period_sec
}

--------------------------------------------------------------------------------
-- Color bar for pomodoor
--------------------------------------------------------------------------------

local function pom_del_indicators()
    pom.bar.c_left:delete()
    pom.bar.c_used:delete()
end

local function pom_draw_on_menu(target_draw, screen, offset, width, fill_color)
    local screeng = screen:fullFrame()
    local screen_frame_height = screen:frame().y
    local screen_full_frame_height = screeng.y
    local height_delta = screen_frame_height - screen_full_frame_height
    local height = pom.bar.indicator_height * (height_delta)

    target_draw:setSize(hs.geometry.rect(screeng.x + offset, screen_full_frame_height, width, height))
    target_draw:setTopLeft(hs.geometry.point(screeng.x + offset, screen_full_frame_height))
    target_draw:setFillColor(fill_color)
    target_draw:setFill(true)
    target_draw:setAlpha(pom.bar.indicator_alpha)
    target_draw:setLevel(hs.drawing.windowLevels.overlay)
    target_draw:setStroke(false)
    if pom.bar.indicator_in_all_spaces then
        target_draw:setBehavior(hs.drawing.windowBehaviors.canJoinAllSpaces)
    end
    target_draw:show()
end

local function pom_draw_indicator(time_left, max_time)
    local main_screen = hs.screen.mainScreen()
    local screeng = main_screen:fullFrame()

    local time_ratio = time_left / max_time
    local width = math.ceil(screeng.w * time_ratio)
    local left_width = screeng.w - width

    pom_draw_on_menu(pom.bar.c_left, main_screen, left_width, width, pom.bar.color_time_remaining)
    pom_draw_on_menu(pom.bar.c_used, main_screen, 0, left_width, pom.bar.color_time_used)

end
--------------------------------------------------------------------------------

-- update display
local function pom_update_display()
    local time_min = math.floor((pom.var.time_left / 60))
    local time_sec = pom.var.time_left - (time_min * 60)
    local str = string.format("[%s|%02d:%02d|#%02d]", pom.var.curr_active_type, time_min, time_sec, pom.var.work_count)
    pom_menu:setTitle(str)
end

-- stop the clock
-- Stateful:
-- * Disabling once will pause the countdown
-- * Disabling twice will reset the countdown
-- * Disabling trice will shut down and hide the pomodoro timer
function pom.disable()
    local pom_was_active = pom.var.is_active
    pom.var.is_active = false

    if (pom.var.disable_count == 0) then
        if (pom_was_active) then
            pom_timer:stop()
        end
    elseif (pom.var.disable_count == 1) then
        pom.var.time_left = pom.config.work_period_sec
        pom.var.curr_active_type = "work"
        pom_update_display()
    elseif (pom.var.disable_count >= 2) then
        if pom_menu == nil then
            pom.var.disable_count = 2
            return
        end

        pom_menu:delete()
        pom_menu = nil
        pom_timer:stop()
        pom_timer = nil
        pom_del_indicators()
    end

    pom.var.disable_count = pom.var.disable_count + 1
end

-- update pomodoro timer
local function pom_update_time()
    if pom.var.is_active == false then
        return
    else
        pom.var.time_left = pom.var.time_left - 1

        if (pom.var.time_left <= 0) then
            pom.disable()
            if pom.var.curr_active_type == "work" then
                hs.alert.show("Work Complete!", 2)
                pom.var.work_count = pom.var.work_count + 1
                pom.var.curr_active_type = "rest"
                pom.var.time_left = pom.config.rest_period_sec
                pom.var.max_time_sec = pom.config.rest_period_sec
            else
                hs.alert.show("Done resting", 2)
                pom.var.curr_active_type = "work"
                pom.var.time_left = pom.config.work_period_sec
                pom.var.max_time_sec = pom.config.work_period_sec
            end
        end

        -- draw color bar indicator, if enabled.
        if (pom.config.enable_color_bar == true) then
            pom_draw_indicator(pom.var.time_left, pom.var.max_time_sec)
        end
    end
end

-- update menu display
local function pom_update_menu()
    pom_update_time()
    pom_update_display()
end

local function pom_create_menu(pom_origin)
    if pom_menu == nil then
        pom_menu = hs.menubar.new()
        pom.bar.c_left = hs.drawing.rectangle(hs.geometry.rect(0, 0, 0, 0))
        pom.bar.c_used = hs.drawing.rectangle(hs.geometry.rect(0, 0, 0, 0))
    end
end

-- start the pomodoro timer
function pom.enable()
    pom.var.disable_count = 0;
    if (pom.var.is_active) then
        return
    end

    pom_create_menu()
    pom_timer = hs.timer.new(1, pom_update_menu)

    pom.var.is_active = true
    pom_timer:start()
end

-- reset work count
function pom.reset_work()
    pom.var.work_count = 0;
end

-- Return the module
return pom
