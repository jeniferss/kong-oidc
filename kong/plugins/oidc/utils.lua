local cjson = require("cjson")

local M = {}

local function parseFilters(csvFilters)
  local filters = {}
  if (not (csvFilters == nil)) then
    for pattern in string.gmatch(csvFilters, "[^,]+") do
      table.insert(filters, pattern)
    end
  end
  return filters
end

function M.get_redirect_uri_path(ngx)
  local function drop_query()
    local uri = ngx.var.request_uri
    local x = uri:find("?")
    if x then
      return uri:sub(1, x - 1)
    else
      return uri
    end
  end

  local function tackle_slash(path)
    local args = ngx.req.get_uri_args()
    if args and args.code then
      return path
    elseif path == "/" then
      return "/cb"
    elseif path:sub(-1) == "/" then
      return path:sub(1, -2)
    else
      return path .. "/"
    end
  end

  return tackle_slash(drop_query())
end

function M.get_options(config, ngx)
  return {
    client_id = config.client_id,
    client_secret = config.client_secret,
    discovery = config.discovery,
    introspection_endpoint = config.introspection_endpoint,
    timeout = config.timeout,
    introspection_endpoint_auth_method = config.introspection_endpoint_auth_method,
    bearer_only = config.bearer_only,
    realm = config.realm,
    redirect_uri_path = config.redirect_uri_path or M.get_redirect_uri_path(ngx),
    scope = config.scope,
    response_type = config.response_type,
    ssl_verify = config.ssl_verify,
    token_endpoint_auth_method = config.token_endpoint_auth_method,
    recovery_page_path = config.recovery_page_path,
    filters = parseFilters(config.filters),
    logout_path = config.logout_path,
    redirect_after_logout_uri = config.redirect_after_logout_uri,
    verify_client_token = config.verify_client_token,
    client_token_public_key = config.client_token_public_key
  }
end

function M.exit(httpStatusCode, message, ngxCode)
  ngx.status = httpStatusCode
  ngx.say(message)
  ngx.exit(ngxCode)
end

function M.injectAccessToken(accessToken)
  ngx.req.set_header("X-Access-Token", accessToken)
end

function M.injectIDToken(idToken)
  local tokenStr = cjson.encode(idToken)
  ngx.req.set_header("X-ID-Token", ngx.encode_base64(tokenStr))
end

function M.injectUser(user)
  local tmp_user = user
  tmp_user.id = user.sub
  tmp_user.username = user.preferred_username
  ngx.ctx.authenticated_credential = tmp_user
  local userinfo = cjson.encode(user)
  ngx.req.set_header("X-Userinfo", ngx.encode_base64(userinfo))
end

function M.has_bearer_access_token()
  local header = ngx.req.get_headers()['Authorization']
  if header and header:find(" ") then
    local divider = header:find(' ')
    if string.lower(header:sub(divider+1)) == string.lower("Bearer") then
      return true
    end
  end
  return false
end

local function tokenize(str, div, len)
  local result, pos = {}, 0

  local iter = function()
    return string.find(str, div, pos, true)
  end

  for st, sp in iter do
    result[#result + 1] = string.sub(str, pos, st-1)
    pos = sp + 1
    len = len - 1
    if len <= 1 then
      break
    end
  end

  result[#result + 1] = string.sub(str, pos)
  return result
end


function GetRoles(header)
  local divider = header:find(' ')
  local token = header:sub(divider+1)
  local header_64, claims_64, signature_64 = unpack(tokenize(token, ".", 3))
  local payload = ngx.decode_base64(claims_64)
  local token_payload = cjson.decode(payload)
  for i, v in next, token_payload do
    print(i, v)
    for n, k in next, v do
        print(">", n, k)
    end
  end
  local scopes = token_payload[10]
  return scopes
end

function M.is_client_token()
  local header = ngx.req.get_headers()['Authorization']
  if header and header:find(" ") then
    local roles = GetRoles(header)
    for role in roles do
      if string.lower(role) == 'client' then
        return true
      end
    end
  end
  return false
end


return M
