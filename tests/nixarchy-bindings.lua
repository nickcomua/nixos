-- Load the actual upstream bindings plus our overrides against a recording
-- compositor API. This detects accidental duplicate actions and upstream drift.
local bindings = {}
local function dispatcher(path)
  return setmetatable({}, {
    __index = function(_, name) return dispatcher(path .. '.' .. name) end,
    __call = function() return path end,
  })
end
hl = {
  dsp = dispatcher('dispatch'),
  unbind = function(key) bindings[key] = nil end,
  on = function() end,
}
o = {
  bind = function(key, description, action, options)
    local id = key .. ((options and options.release) and ':release' or '')
    bindings[id] = bindings[id] or {}
    table.insert(bindings[id], {description = description, action = action})
  end,
  bind_toggle = function(key, description, action)
    o.bind(key, description, action)
  end,
  preinstalled_bindings_enabled = function() return true end,
  cmd_present = function() return false end,
}
for _, name in ipairs({'tiling', 'utilities', 'applications', 'clipboard', 'media', 'voxtype'}) do
  dofile(os.getenv('OMARCHY_SOURCE') .. '/default/hypr/bindings/' .. name .. '.lua')
end
dofile('flake-parts/hosts/nixos/desktop/files/.config/hypr/bindings.lua')
assert(bindings['SUPER + W'] == nil, 'Super+W must stay unbound')
local expected = {
  ['SUPER + Q'] = 'Close window',
  ['SUPER + RETURN'] = 'Ghostty',
  ['SUPER + E'] = 'Yazi',
  ['SUPER + L'] = 'Toggle workspace layout',
  ['SUPER + S'] = 'Toggle scratchpad',
  ['SUPER + TAB'] = 'Next workspace',
  ['SUPER + V'] = 'Universal paste',
  ['SUPER + CTRL + V'] = 'Clipboard manager',
  ['SUPER + ESCAPE'] = 'System menu',
  ['SUPER + comma'] = 'Dismiss last notification',
  ['PRINT'] = 'Screenshot',
  ['CTRL + grave'] = 'Start dictation',
  ['CTRL + grave:release'] = 'Stop dictation',
}
for key, description in pairs(expected) do
  assert(bindings[key] and #bindings[key] == 1, 'Missing/duplicate action for ' .. key)
  assert(bindings[key][1].description == description, 'Unexpected action for ' .. key)
end
assert(bindings['SHIFT + PRINT'] == nil)
assert(bindings['CTRL + SHIFT + PRINT'] == nil)
print('Upstream and personal bindings compose correctly.')
