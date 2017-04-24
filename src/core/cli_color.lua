local cli_colors = {}

-- default colors if ROSIE_COLORS isn't defined in the environment
--cli_colors.default_colors = "rs=0:di=38;5;33:ln=38;5;51:mh=00:pi=40;38;5;11:so=38;5;13:do=38;5;5:bd=48;5;232;38;5;11:cd=48;5;232;38;5;3:or=48;5;232;38;5;9:"
cli_colors.default_colors = table.concat({
	".=30",
	"basic.unmatched=30",
	"simplified_json=33",
	"common.word=33",
	"common.int=4",
	"common.float=4",
	"common.mantissa=4",
	"common.exp=4",
	"common.hex=4",
	"common.denoted_hex=4",
	"common.number=4",
	"common.maybe_identifier=36",
	"common.identifier_not_word=36",
	"common.identifier_plus=36",
	"common.identifier_plus_plus=36",
	"common.path=32",
	"basic.datetime_patterns=34",
	"basic.netwok_patterns=31",
	"datetime.datetime_RFC3339=34",
	"datetime.slash_datetime=34",
	"datetime.simple_slash_date=34",
	"datetime.shortdate=34",
	"datetime.ordinary_date=34",
	"datetime.simple_date=34",
	"datetime.simple_datetime=34",
	"datetime.full_date_RFC3339=34",
	"datetime.date_RFC2822=34",
	"datetime.time_RFC2822=34",
	"datetime.full_time_RFC2822=34",
	"datetime.simple_time=34",
	"datetime.funny_time=34",
	"network.http_command=31",
	"network.url=31",
	"network.http_version=31",
	"network.ip_address=31",
	"network.fqdn=31",
	"network.email_address=31",
	}, ":") -- use table.concat to join all to a string with a : delimiter
-- raw ROSIE_COLORS string
cli_colors._rosie_colors_raw = nil
-- a table with type as the key and color code as value
cli_colors._rosie_color = {}

-- for debugging purposes, can pass another environment variable name such as LS_COLORS
-- if debug is nil, uses ROSIE_COLORS
-- if getenv returns nil, defaults to cli_colors.default_colors
function cli_colors.get_rosie_colors(debug)
	local raw = os.getenv(debug or "ROSIE_COLORS") or cli_colors.default_colors
	local tbl = {}
	-- loop through all the key=value pairs
	for color in raw:gmatch("([^:]+)") do
		-- put them in the table
		color:gsub("([^=]+)=(.+)", function(k,v) tbl[k] = v end)
	end
	-- save the raw string and the table
	cli_colors._rosie_colors_raw = raw
	cli_colors._rosie_color = tbl
end

-- wrap a string in its type color, or just return the string if type isn't defined
-- will call get_rosie_colors if raw string is nil (default value)
-- returns false, str if no type found
-- returns true, colored_string if type found
function cli_colors.color_string(str, t)
	if not cli_colors._rosie_colors_raw then
		cli_colors.get_rosie_colors()
	end
	if not cli_colors._rosie_color[t] then
		return false, str
	end
	return true, "\027["..cli_colors._rosie_color[t].."m"..str.."\027[0m"
end

return cli_colors
