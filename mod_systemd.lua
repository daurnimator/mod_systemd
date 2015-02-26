-- Copyright (C) 2014 Daurnimator
-- Released under MIT/X11 license

-- Uses https://github.com/daurnimator/lua-systemd

local sd = require "systemd.daemon"
local sj = require "systemd.journal"

module:set_global() -- Global module

local function ready()
	sd.notifyt { READY = 1, STATUS = "running" };
end
module:hook("server-starting", function()
	sd.notifyt { STATUS = "server-starting" };
end)
module:hook("server-started", ready)
module:hook("server-stopping", function()
	sd.notifyt { STOPPING = 1, STATUS = "server-stopping" };
end)
module:hook("server-stopped", function()
	sd.notifyt { STATUS = "server-stopped" };
end)
module:hook("config-reloaded", function()
	sd.notifyt { RELOADING = 1, STATUS = "config-reloading" };
end, 100)
module:hook("config-reloaded", ready, -100)

-- log direct to the systemd journal
local priorities = {
	error = 2; -- Prosody maps error to critical
	warn = 4;
	info = 6;
	debug = 7;
}
require "core.loggingmanager".register_sink_type("journal", function(config)
	local identifier = config.identifier or module:get_option_string("syslog_identifier", _G.arg[0]:gsub(".*/",""));
	local facility = config.facility or module:get_option_string("syslog_facility")
	local with_code = config.debug_info
	local stack_frame = 3
	return function(name, level, ...)
		local m = {
			SYSLOG_IDENTIFIER = identifier;
			SYSLOG_FACILITY = facility;
			PROSODY_COMPONENT = name;
			PRIORITY = priorities[level];
			MESSAGE = string.format(...);
		};
		if with_code then
			local info = debug.getinfo(stack_frame, "nlS");
			m.CODE_FILE = info.short_src;
			if info.currentline ~= -1 then
				m.CODE_LINE = info.currentline;
			end
			m.CODE_FUNC = info.name;
		end
		sj.sendt(m);
	end
end)

-- If we have a systemd watchdog, keep it awake
local watchdog_interval = sd.watchdog_enabled()
if watchdog_interval then
	watchdog_interval = watchdog_interval/2
	module:log("debug", "Enabling watchdog with interval of %f", watchdog_interval)
	module:add_timer(watchdog_interval, function()
		sd.kick_dog()
		return watchdog_interval
	end)
end
