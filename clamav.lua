local M		= {}
local parser	= require "clamav.parser"
local http	= require "resty.http"
local cjson	= require "cjson"
local logger	= require "logger"

function M.check ()
	-- Only scan if there is at least one file
	if ngx.var.http_content_type == nil or string.match(ngx.var.http_content_type, "boundary=(.*)") == nil then
		return
	end
	local body = ngx.req.get_body_data()
	local p, err = parser.new(body, ngx.var.http_content_type)
	if not p then
		logger.log(ngx.ERR, "CLAMAV", "Failed to create parser : " .. err)
		return
	end
	local boundary = "--" .. string.match(ngx.var.http_content_type, "boundary=(.*)")
	local new_body = ""
	local i = 0
	while true do
		local part_body, name, mime, filename = p:parse_part()
		if not part_body then
			break
		end
		if filename ~= nil then
			if new_body ~= "" then
				new_body = new_body .. "\r\n"
			end
			new_body = new_body .. boundary .. "\r\n" .. "Content-Disposition: form-data; name=\"FILES\"; filename=\"" .. filename .. "\"\r\nContent-Type: " .. mime .. "\r\n\r\n" .. part_body .. "\r\n" .. boundary
			i = i + 1
		end
	end
	if new_body == "" then
		return
	end
	new_body = new_body .. "--" .. "\r\n"

	-- Get the remote endpoint address
	local remote_clamav_rest_api, flags = ngx.shared.plugins_data:get("clamav_REMOTE_CLAMAV_REST_API")
	if remote_clamav_rest_api == nil then
		logger.log(ngx.ERR, "CLAMAV", "Plugin is enabled but REMOTE_CLAMAV_REST_API is missing.")
		return
	end

	-- Forward to API
	local httpc = http.new()
	local res, err = httpc:request_uri(remote_clamav_rest_api .. "/api/v1/scan", {
		ssl_verify = false,
		method = "POST",
		body = new_body,
		headers = { ["Content-Type"] = ngx.var.http_content_type }
	})
	if not res then
		logger.log(ngx.ERR, "CLAMAV", "Error while sending request to " .. remote_clamav_rest_api)
		return
	end
	if res.status ~= 200 then
		logger.log(ngx.ERR, "CLAMAV", "Wrong status code from API : " .. res.status)
		return
	end

	-- Infected or not ?
	local result = cjson.decode(res.body)
	if not result.success then
		logger.log(ngx.ERR, "CLAMAV", "API call failed (success = false)")
		return
	end
	local infected = false
	for i, report in ipairs(result.data.result) do
		if report.is_infected then
			infected = true
			for j, virus in ipairs(report.viruses) do
				logger.log(ngx.WARN, "CLAMAV", "Detected infected file : " .. virus)
			end
		else
			logger.log(ngx.INFO, "CLAMAV", "File " .. report.name .. " is clean")
		end
	end
	if infected then
		ngx.exit(ngx.HTTP_FORBIDDEN)
	end
end

return M
