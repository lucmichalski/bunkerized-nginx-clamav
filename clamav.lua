local M		= {}
local http	= require "resty.http"
local logger	= require "logger"
local upload	= require "clamav.upload"

function M.check ()
	-- Check if there is at least a file
	local form, err = upload:new(4096)
	if not form then
		logger.log(ngx.ERR, "CLAMAV", "Error new upload : " .. err)
		return
	end
	form:set_timeout(1000)
	local is_file = false
	while true do
		local typ, res, err = form:read()
		if not type then
			logger.log(ngx.ERR, "CLAMAV", "Error read form : " .. err)
			return
		end
		-- Is it a header containing filename= ?
		if typ == "header" and string.match(res["Content-Disposition"], "filename=") then
			is_file = true
			break
		-- Is it the end of the form ?
		elseif typ == "eof" then
			break
		end
	end
	if not is_file then
		return
	end

	-- Get the remote endpoint address
	local remote_clamav_rest_api, flags = ngx.shared.plugins_data:get("clamav_REMOTE_CLAMAV_REST_API")
	if remote_clamav_rest_api == nil then
		logger.log(ngx.ERR, "CLAMAV", "Plugin is enabled but REMOTE_CLAMAV_REST_API is missing.")
		return
	end

	-- Forward to API
	local httpc = http.new()
	local res, err = httpc:request_uri(remote_clamav_rest_api .. "/scan", {
		method = "POST",
		body = ngx.req.get_body_data(),
		headers = ngx.req.get_headers()
	})
	if not res then
		logger.log(ngx.ERR, "CLAMAV", "Error while sending request to " .. remote_clamav_rest_api)
		return
	end
	if res.status ~= "200" then
		logger.log(ngx.ERR, "CLAMAV", "Wrong status code from API : " .. res.status)
		return
	end

	-- Infected or not ?
	if not string.match(res.body, "Everything ok : true") then
		logger.log(ngx.WARN, "CLAMAV", "Detected infected file(s) : " .. res.body)
		ngx.exit(ngx.HTTP_FORBIDDEN)
	end
	logger.log(ngx.NOTICE, "CLAMAV", "Every files are clean !")
end

return M
