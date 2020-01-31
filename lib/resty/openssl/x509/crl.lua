local ffi = require "ffi"
local C = ffi.C
local ffi_gc = ffi.gc

require "resty.openssl.include.x509.crl"
require "resty.openssl.include.pem"
require "resty.openssl.include.x509v3"
local asn1_lib = require("resty.openssl.asn1")
local digest_lib = require("resty.openssl.digest")
local extension_lib = require("resty.openssl.x509.extension")
local pkey_lib = require("resty.openssl.pkey")
local util = require "resty.openssl.util"
local txtnid2nid = require("resty.openssl.objects").txtnid2nid
local format_error = require("resty.openssl.err").format_error

local OPENSSL_10 = require("resty.openssl.version").OPENSSL_10
local OPENSSL_11 = require("resty.openssl.version").OPENSSL_11

local accessors = {}

accessors.set_issuer_name = C.X509_CRL_set_issuer_name

if OPENSSL_11 then
  accessors.get_last_update = C.X509_CRL_get0_lastUpdate
  accessors.set_last_update = C.X509_CRL_set1_lastUpdate
  accessors.get_next_update = C.X509_CRL_get0_nextUpdate
  accessors.set_next_update = C.X509_CRL_set1_nextUpdate
  accessors.get_version = C.X509_CRL_get_version
  accessors.get_issuer_name = C.X509_CRL_get_issuer -- returns internal ptr
elseif OPENSSL_10 then
  accessors.get_last_update = function(crl)
    if crl == nil or crl.crl == nil then
      return nil
    end
    return crl.crl.lastUpdate
  end
  accessors.set_last_update = C.X509_CRL_set_lastUpdate
  accessors.get_next_update = function(crl)
    if crl == nil or crl.crl == nil then
      return nil
    end
    return crl.crl.nextUpdate
  end
  accessors.set_next_update = C.X509_CRL_set_nextUpdate
  accessors.get_version = function(crl)
    if crl == nil or crl.crl == nil then
      return nil
    end
    return C.ASN1_INTEGER_get(crl.crl.version)
  end
  accessors.get_issuer_name = function(crl)
    if crl == nil or crl.crl == nil then
      return nil
    end
    return crl.crl.issuer
  end
end

local function tostring(self, fmt)
  if not fmt or fmt == 'PEM' then
    return util.read_using_bio(C.PEM_write_bio_X509_CRL, self.ctx)
  elseif fmt == 'DER' then
    return util.read_using_bio(C.i2d_X509_CRL_bio, self.ctx)
  else
    return nil, "can only write PEM or DER format, not " .. fmt
  end
end

local _M = {}
local mt = { __index = _M, __tostring = tostring }

local x509_crl_ptr_ct = ffi.typeof("X509_CRL*")

function _M.new(crl, fmt)
  local ctx
  if not crl then
    C.X509_CRL_new()
    if ctx == nil then
      return nil, "X509_CRL_new() failed"
    end
  elseif type(crl) == "string" then
    -- routine for load an existing csr
    local bio = C.BIO_new_mem_buf(crl, #crl)
    if bio == nil then
      return nil, format_error("x509.crl.new: BIO_new_mem_buf")
    end

    fmt = fmt or "*"
    while true do
      if fmt == "PEM" or fmt == "*" then
        ctx = C.PEM_read_bio_X509_CRL(bio, nil, nil, nil)
        if ctx ~= nil then
          break
        end
      end
      if fmt == "DER" or fmt == "*" then
        ctx = C.d2i_X509_CRL_bio(bio, nil)
      end
      break
    end
    C.BIO_free(bio)
    if ctx == nil then
      return nil, format_error("x509.crl.new")
    end
  else
    return nil, "expect nil or a string at #1"
  end
  ffi_gc(ctx, C.X509_CRL_free)

  local self = setmetatable({
    ctx = ctx,
  }, mt)

  return self, nil
end

function _M.istype(l)
  return l and l and l.ctx and ffi.istype(x509_crl_ptr_ct, l.ctx)
end

function _M.dup(ctx)
  if not ffi.istype(x509_crl_ptr_ct, ctx) then
    return nil, "expect a x509.crl ctx at #1"
  end
  local ctx = C.X509_CRL_dup(ctx)
  if ctx == nil then
    return nil, "X509_CRL_dup() failed"
  end

  ffi_gc(ctx, C.X509_CRL_free)

  local self = setmetatable({
    ctx = ctx,
  }, mt)

  return self, nil
end

function _M:tostring(fmt)
  return tostring(self, fmt)
end

function _M:to_PEM()
  return tostring(self, "PEM")
end

-- START AUTO GENERATED CODE

-- AUTO GENERATED
function _M:sign(pkey, digest)
  if not pkey_lib.istype(pkey) then
    return false, "expect a pkey instance at #1"
  end
  if digest and not digest_lib.istype(digest) then
    return false, "expect a digest instance at #2"
  end

  -- returns size of signature if success
  if C.X509_CRL_sign(self.ctx, pkey.ctx, digest and digest.ctx) == 0 then
    return false, format_error("crl:sign")
  end

  return true
end

-- AUTO GENERATED
function _M:verify(pkey)
  if not pkey_lib.istype(pkey) then
    return false, "expect a pkey instance at #1"
  end

  local code = C.X509_CRL_verify(self.ctx, pkey.ctx)
  if code == 1 then
    return true
  elseif code == 0 then
    return false
  else -- typically -1
    return false, format_error("crl:verify", code)
  end

  return true
end

-- AUTO GENERATED
local function get_extension(ctx, nid_txt, last_pos)
  last_pos = (last_pos or 0) - 1
  local nid, err = txtnid2nid(nid_txt)
  if err then
    return nil, nil, err
  end
  local pos = C.X509_CRL_get_ext_by_NID(ctx, nid, last_pos)
  if pos == -1 then
    return nil
  end
  local ctx = C.X509_CRL_get_ext(ctx, pos)
  if ctx == nil then
    return nil, nil, format_error("crl:get_extension")
  end
  return ctx, pos
end

-- AUTO GENERATED
function _M:add_extension(extension)
  if not extension_lib.istype(extension) then
    return false, "expect a x509.extension instance at #1"
  end

  -- X509_CRL_add_ext returnes the stack on success, and NULL on error
  -- the X509_EXTENSION ctx is dupped internally
  if C.X509_CRL_add_ext(self.ctx, extension.ctx, -1) == nil then
    return false, format_error("crl:add_extension")
  end

  return true
end

-- AUTO GENERATED
function _M:get_extension(nid_txt, last_pos)
  local ctx, pos, err = get_extension(self.ctx, nid_txt, last_pos)
  if err then
    return nil, nil, err
  end
  local ext, err = extension_lib.dup(ctx)
  if err then
    return nil, nil, err
  end
  return ext, pos+1
end

local X509_CRL_delete_ext
if OPENSSL_11 then
  X509_CRL_delete_ext = C.X509_CRL_delete_ext
elseif OPENSSL_10 then
  X509_CRL_delete_ext = function(ctx, pos)
    return C.X509v3_delete_ext(ctx.crl.extensions, pos)
  end
else
  X509_CRL_delete_ext = function(...)
    error("X509_CRL_delete_ext undefined")
  end
end

-- AUTO GENERATED
function _M:set_extension(extension, last_pos)
  if not extension_lib.istype(extension) then
    return false, "expect a x509.extension instance at #1"
  end

  last_pos = (last_pos or 0) - 1

  local nid = extension:get_object().nid
  local pos = C.X509_CRL_get_ext_by_NID(self.ctx, nid, last_pos)
  if pos == -1 then
    return nil
  end

  local removed = X509_CRL_delete_ext(self.ctx, pos)
  C.X509_EXTENSION_free(removed)

  if C.X509_CRL_add_ext(self.ctx, extension.ctx, pos) == nil then
    return false, format_error("crl:set_extension")
  end

  return true
end

-- AUTO GENERATED
function _M:set_extension_critical(nid_txt, crit, last_pos)
  local ctx, _, err = get_extension(self.ctx, nid_txt, last_pos)
  if err then
    return nil, err
  end

  if C.X509_EXTENSION_set_critical(ctx, crit and 1 or 0) ~= 1 then
    return false, format_error("crl:set_extension_critical")
  end

  return true
end

-- AUTO GENERATED
function _M:get_extension_critical(nid_txt, last_pos)
  local ctx, _, err = get_extension(self.ctx, nid_txt, last_pos)
  if err then
    return nil, err
  end

  return C.X509_EXTENSION_get_critical(ctx) == 1
end

-- AUTO GENERATED
function _M:get_issuer_name()
  local got = accessors.get_issuer_name(self.ctx)
  if got == nil then
    return nil, format_error("crl:get_issuer_name")
  end
  local lib = require("resty.openssl.x509.name")
  -- the internal ptr is returned, ie we need to copy it
  return lib.dup(got)
end

-- AUTO GENERATED
function _M:set_issuer_name(toset)
  local lib = require("resty.openssl.x509.name")
  if lib.istype and not lib.istype(toset) then
    return false, "expect a x509.name instance at #1"
  end
  toset = toset.ctx
  if accessors.set_issuer_name(self.ctx, toset) == 0 then
    return false, format_error("crl:set_issuer_name")
  end

  return true
end

-- AUTO GENERATED
function _M:get_last_update()
  local got = accessors.get_last_update(self.ctx)
  if got == nil then
    return nil, format_error("crl:get_last_update")
  end

  got = asn1_lib.asn1_to_unix(got)

  return got
end

-- AUTO GENERATED
function _M:set_last_update(toset)
  if type(toset) ~= "number" then
    return false, "expect a number at #1"
  end

  toset = C.ASN1_TIME_set(nil, toset)
  ffi_gc(toset, C.ASN1_STRING_free)

  if accessors.set_last_update(self.ctx, toset) == 0 then
    return false, format_error("crl:set_last_update")
  end

  return true
end

-- AUTO GENERATED
function _M:get_next_update()
  local got = accessors.get_next_update(self.ctx)
  if got == nil then
    return nil, format_error("crl:get_next_update")
  end

  got = asn1_lib.asn1_to_unix(got)

  return got
end

-- AUTO GENERATED
function _M:set_next_update(toset)
  if type(toset) ~= "number" then
    return false, "expect a number at #1"
  end

  toset = C.ASN1_TIME_set(nil, toset)
  ffi_gc(toset, C.ASN1_STRING_free)

  if accessors.set_next_update(self.ctx, toset) == 0 then
    return false, format_error("crl:set_next_update")
  end

  return true
end

-- AUTO GENERATED
function _M:get_version()
  local got = accessors.get_version(self.ctx)
  if got == nil then
    return nil, format_error("crl:get_version")
  end

  got = tonumber(got) + 1

  return got
end

-- AUTO GENERATED
function _M:set_version(toset)
  if type(toset) ~= "number" then
    return false, "expect a number at #1"
  end

  -- Note: this is defined by standards (X.509 et al) to be one less than the certificate version.
  -- So a version 3 certificate will return 2 and a version 1 certificate will return 0.
  toset = toset - 1

  if accessors.set_version(self.ctx, toset) == 0 then
    return false, format_error("crl:set_version")
  end

  return true
end


-- END AUTO GENERATED CODE

return _M

