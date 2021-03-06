local helpers = require "spec.helpers"
local cache = require "kong.tools.database_cache"
local cjson = require "cjson"

describe("Plugin: key-auth (hooks)", function()
  local admin_client, proxy_client
  setup(function()
    assert(helpers.start_kong())
    proxy_client = helpers.proxy_client()
    admin_client = helpers.admin_client()
  end)
  teardown(function()
    if admin_client and proxy_client then
      admin_client:close()
      proxy_client:close()
    end
    helpers.stop_kong()
  end)

  before_each(function()
    helpers.dao:truncate_tables()
    local api = assert(helpers.dao.apis:insert {
      request_host = "key-auth.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api.id
    })

    local consumer = assert(helpers.dao.consumers:insert {
      username = "bob"
    })
    assert(helpers.dao.keyauth_credentials:insert {
      key = "kong",
      consumer_id = consumer.id
    })
  end)

  it("invalidates credentials when the Consumer is deleted", function()
    -- populate cache
    local res = assert(proxy_client:send {
      method = "GET",
      path = "/",
      headers = {
        ["Host"] = "key-auth.com",
        ["apikey"] = "kong"
      }
    })
    assert.res_status(200, res)

    -- ensure cache is populated
    local cache_key = cache.keyauth_credential_key("kong")
    res = assert(admin_client:send {
      method = "GET",
      path = "/cache/"..cache_key
    })
    assert.res_status(200, res)

    -- delete Consumer entity
    res = assert(admin_client:send {
      method = "DELETE",
      path = "/consumers/bob"
    })
    assert.res_status(204, res)

    -- ensure cache is invalidated
    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/"..cache_key
      })
      res:read_body()
      return res.status == 404
    end)

    res = assert(proxy_client:send {
      method = "GET",
      path = "/",
      headers = {
        ["Host"] = "key-auth.com",
        ["apikey"] = "kong"
      }
    })
    assert.res_status(403, res)
  end)

  it("invalidates credentials from cache when deleted", function()
    -- populate cache
    local res = assert(proxy_client:send {
      method = "GET",
      path = "/",
      headers = {
        ["Host"] = "key-auth.com",
        ["apikey"] = "kong"
      }
    })
    assert.res_status(200, res)

    -- ensure cache is populated
    local cache_key = cache.keyauth_credential_key("kong")
    res = assert(admin_client:send {
      method = "GET",
      path = "/cache/"..cache_key
    })
    local body = assert.res_status(200, res)
    local credential = cjson.decode(body)

    -- delete credential entity
    res = assert(admin_client:send {
      method = "DELETE",
      path = "/consumers/bob/key-auth/"..credential.id
    })
    assert.res_status(204, res)

    -- ensure cache is invalidated
    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/"..cache_key
      })
      res:read_body()
      return res.status == 404
    end)

    res = assert(proxy_client:send {
      method = "GET",
      path = "/",
      headers = {
        ["Host"] = "key-auth.com",
        ["apikey"] = "kong"
      }
    })
    assert.res_status(403, res)
  end)

  it("invalidated credentials from cache when updated", function()
    -- populate cache
    local res = assert(proxy_client:send {
      method = "GET",
      path = "/",
      headers = {
        ["Host"] = "key-auth.com",
        ["apikey"] = "kong"
      }
    })
    assert.res_status(200, res)

    -- ensure cache is populated
    local cache_key = cache.keyauth_credential_key("kong")
    res = assert(admin_client:send {
      method = "GET",
      path = "/cache/"..cache_key
    })
    local body = assert.res_status(200, res)
    local credential = cjson.decode(body)

    -- delete credential entity
    res = assert(admin_client:send {
      method = "PATCH",
      path = "/consumers/bob/key-auth/"..credential.id,
      body = {
        key = "kong-updated"
      },
      headers = {
        ["Content-Type"] = "application/json"
      }
    })
    assert.res_status(200, res)

    -- ensure cache is invalidated
    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/"..cache_key
      })
      res:read_body()
      return res.status == 404
    end)

    res = assert(proxy_client:send {
      method = "GET",
      path = "/",
      headers = {
        ["Host"] = "key-auth.com",
        ["apikey"] = "kong"
      }
    })
    assert.res_status(403, res)

    res = assert(proxy_client:send {
      method = "GET",
      path = "/",
      headers = {
        ["Host"] = "key-auth.com",
        ["apikey"] = "kong-updated"
      }
    })
    assert.res_status(200, res)
  end)
end)
