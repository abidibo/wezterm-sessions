local wezterm = require("wezterm")
local pub = {}

-- Helper function to create a timer
function pub.set_interval(fn, interval_s)
	local stopped = false

	local function tick()
		if stopped then
			return
		end

		fn()

		wezterm.time.call_after(interval_s, tick)
	end

	wezterm.time.call_after(interval_s, tick)

	-- stop function
	return function()
		stopped = true
	end
end

return pub
