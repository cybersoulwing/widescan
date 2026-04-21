addon.name    = 'widescan'
addon.author  = 'Silkrea'
addon.version = '1.0'
addon.desc    = 'WideScan'

require('common')
local fonts = require('fonts')
local bit = require('bit')

-- =========================
-- 設定
-- =========================
local MAX_DISTANCE = 50
local SCAN_INTERVAL = 0.1

-- =========================
-- 状態
-- =========================
local scan = { font = nil }
local cached_mobs = {}
local last_scan_time = 0

local selfpos = {
    x = nil,
    y = nil,
    z = nil,
    rot = nil
}

-- =========================
-- 初期化
-- =========================
ashita.events.register('load', 'load_cb', function ()
    scan.font = fonts.new({
        visible = true,
        font_family = 'Consolas',
        font_height = 12,
        color = 0xFFFFFFFF,
        bold = true,
        position_x = 20,
        position_y = 120,
        text = ''
    })
end)

-- =========================
-- 終了
-- =========================
ashita.events.register('unload', 'unload_cb', function ()
    if scan.font then
        scan.font:destroy()
        scan.font = nil
    end
end)

-- =========================
-- 自分座標取得
-- =========================
ashita.events.register('packet_out', 'move_debug', function (e)

    if (e.id ~= 0x015) then
        return
    end

    local packet = e.data

    selfpos.x = struct.unpack('f', packet, 5)
    selfpos.z = struct.unpack('f', packet, 9)
    selfpos.y = struct.unpack('f', packet, 13)
    selfpos.rot = struct.unpack('B', packet, 21)

end)

-- =========================
-- mobスキャン
-- =========================
local function scan_entities()

    local list = {}

    for i = 0, 2303 do

        local ent = GetEntity(i)

        if ent ~= nil then

            local name = ent.Name
            local spawn = ent.SpawnFlags
            local hp = ent.HPPercent

            if name and name ~= '' and spawn and hp then

                if hp > 0 and bit.band(spawn, 0x10) ~= 0 then

                    list[#list + 1] = {
                        index = i,
                        name = name
                    }

                end
            end
        end
    end

    return list
end

-- =========================
-- 距離計算（XY平面）
-- =========================
local function get_distance(sx, sy, tx, ty)

    if not sx or not sy or not tx or not ty then
        return nil
    end

    local dx = tx - sx
    local dy = ty - sy

    return math.sqrt(dx * dx + dy * dy)
end

-- =========================
-- 相対方向
-- =========================
local function get_relative_direction(sx, sy, tx, ty)

    if not sx or not sy or not tx or not ty then
        return "?"
    end

    local dx = tx - sx
    local dy = ty - sy

    local deg = math.deg(math.atan2(dx, dy))

    if deg < 0 then
        deg = deg + 360
    end

    if deg >= 337.5 or deg < 22.5 then return "N"
    elseif deg < 67.5 then return "NE"
    elseif deg < 112.5 then return "E"
    elseif deg < 157.5 then return "SE"
    elseif deg < 202.5 then return "S"
    elseif deg < 247.5 then return "SW"
    elseif deg < 292.5 then return "W"
    else return "NW"
    end
end

-- =========================
-- 描画
-- =========================
ashita.events.register('d3d_present', 'present_cb', function ()

    if not scan.font then return end

    local now = os.clock()

    if (now - last_scan_time) > SCAN_INTERVAL then
        cached_mobs = scan_entities()
        last_scan_time = now
    end

    local entMgr = AshitaCore:GetMemoryManager():GetEntity()
    local mobs = {}

    for i = 1, #cached_mobs do

        local m = cached_mobs[i]
        local ent = GetEntity(m.index)

        if ent then

            local x = entMgr:GetLocalPositionX(m.index)
            local y = entMgr:GetLocalPositionY(m.index)

            if x and y then

                local d = get_distance(selfpos.x, selfpos.y, x, y)

                if d and d > 0 and d <= MAX_DISTANCE then
                    mobs[#mobs + 1] = {
                        name = m.name,
                        x = x,
                        y = y,
                        d = d
                    }
                end
            end
        end
    end

    -- 距離ソート
    table.sort(mobs, function(a, b)
        return a.d < b.d
    end)

    -- =========================
    -- 自分座標
    -- =========================
    local sx = selfpos.x
    local sy = selfpos.y

    -- =========================
    -- 表示
    -- =========================
    local t = {}

    t[#t + 1] = '===== WideScan GPS ====='

    if sx and sy then
        t[#t + 1] = string.format('Self Pos: [%.2f, %.2f]', sx, sy)
    else
        t[#t + 1] = 'Self Pos: waiting packet...'
    end

    t[#t + 1] = '----------------------------------'

    local shown = 0

    for i = 1, #mobs do

        shown = shown + 1
        if shown > 20 then break end

        local m = mobs[i]

        local dir = get_relative_direction(sx, sy, m.x, m.y)

        t[#t + 1] = string.format(
            '%-18s %6.1f  %s',
            m.name,
            m.d,
            dir
        )
    end

    scan.font.text = table.concat(t, '\n')
end)