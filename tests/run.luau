--!strict
--!native
-- load-order's own cases, on load orders built in scratch: an openmw.cfg, its data folders, and
-- content files made of bytes (`fixtures.luau`), opened through a real `@openmw` Context.
local fixtures = require './fixtures'
local fs = require '@dream/fs'
local loadOrder = require '@load-order'
local openmw = require '@openmw'
local tes3 = require '@tes3'
local test = require '@jess/test'

local expect = test.expect
local suite = test.new()
local scratch = assert(rawget(_G, 'scratchRoot') :: string?, 'the suite needs a host-owned scratchRoot')

local function io<Value>(value: Value?, message: string?, kind: dream_fs_ErrorKind?): Value
  if not value then error(message or tostring(kind), 0) end

  return value
end

--- A configuration folder named `name` holding `config` as its openmw.cfg and `files` by their
--- paths under it; the folder, and the Context over the configuration.
local function order(name: string, config: string, files: { [string]: string }?): (string, openmw.Context)
  local directory = jess.fs.join(scratch, 'load-order', name)
  io(fs.mkdir(directory, { recursive = true }))
  for path, bytes in files or {} do
    local file = jess.fs.join(directory, path)
    io(fs.mkdir(jess.fs.parent(file) :: string, { recursive = true }))
    io(fs.writeFile(file, bytes))
  end

  local path = jess.fs.join(directory, 'openmw.cfg')
  io(fs.writeFile(path, config))
  return directory, openmw.new(path)
end

local function names(loaded: { loadOrder.Loaded }): { string }
  local out = {}
  for _, entry in loaded do
    table.insert(out, entry.name)
  end

  return out
end

local function tags(plugin: tes3.Plugin): { string }
  local out = {}
  for index = 0, plugin:count() - 1 do
    table.insert(out, plugin:tag(index))
  end

  return out
end

local Base = fixtures.plugin { fixtures.static 'rock', fixtures.light 'torch' }
local Addon = fixtures.plugin({ fixtures.light 'lamp' }, { { name = 'Base.esm', size = #Base } })

suite.describe('opening', function()
  suite.it('opens the content files in load order, with each file\'s size', function()
    local directory, context = order(
      'content',
      'data=data\ndata=more\ncontent=Base.esm\ncontent=Addon.esp\ncontent=Scripts.omwscripts\n',
      {
        ['data/Base.esm'] = Base,
        ['more/addon.ESP'] = Addon,
        ['data/Scripts.omwscripts'] = 'PLAYER: scripts/player.lua\n',
      }
    )
    local opened = loadOrder.open(context)
    expect(opened.encoding).toBe 'win1252'
    expect(opened.failures).toEqual {}
    expect(names(opened.plugins)).toEqual { 'Base.esm', 'Addon.esp' }

    local base, addon = opened.plugins[1], opened.plugins[2]
    expect(base.path).toBe(jess.fs.join(directory, 'data/Base.esm'))
    expect(base.size).toBe(#Base)
    expect(tags(base.plugin)).toEqual { 'TES3', 'STAT', 'LIGH' }
    -- The name is the configuration's; the path is the file a data folder has for it.
    expect(addon.path).toBe(jess.fs.join(directory, 'more/addon.ESP'))
    expect(addon.size).toBe(#Addon)
    expect(tes3.records.id(addon.plugin, 1)).toBe 'lamp'
    expect(addon.plugin:masters()[1].name).toBe 'Base.esm'
    -- Nothing was left out, so a plugin saves as the bytes it was read from.
    expect(buffer.tostring(addon.plugin:save())).toBe(Addon)
  end)

  suite.it('reports what doesn\'t open, and opens the rest', function()
    local directory, context = order(
      'failures',
      'data=data\ncontent=Base.esm\ncontent=Missing.esp\ncontent=Broken.esp\ncontent=Addon.esp\n',
      { ['data/Base.esm'] = Base, ['data/Broken.esp'] = 'not a plugin', ['data/Addon.esp'] = Addon }
    )
    local opened = loadOrder.open(context)
    expect(names(opened.plugins)).toEqual { 'Base.esm', 'Addon.esp' }

    local broken = jess.fs.join(directory, 'data/Broken.esp')
    expect(opened.failures).toEqual {
      { name = 'Missing.esp', problem = 'no data folder has \'Missing.esp\'' },
      {
        name = 'Broken.esp',
        path = broken,
        problem = `failed to parse '{broken}': truncated record header at offset 0`,
      },
    }
  end)

  suite.it('says why a file it was pointed at can\'t be read', function()
    local directory, context = order('unreadable', 'data=data\n', { ['data/Base.esm'] = Base })
    local gone = jess.fs.join(directory, 'data/Gone.esp')
    local folder = jess.fs.join(directory, 'data')
    local opened = loadOrder.open(context, {
      entries = {
        { name = 'Gone.esp', path = gone },
        { name = 'Folder.esp', path = folder },
        { name = 'Base.esm', path = jess.fs.join(directory, 'data/Base.esm') },
      },
    })
    expect(names(opened.plugins)).toEqual { 'Base.esm' }
    expect(opened.failures).toEqual {
      {
        name = 'Gone.esp',
        path = gone,
        problem = `failed to read '{gone}': No such file or directory (os error 2)`,
      },
      {
        name = 'Folder.esp',
        path = folder,
        problem = `failed to read '{folder}': Is a directory (os error 21)`,
      },
    }
  end)

  suite.it('opens a file that frames as records, whatever is in it', function()
    local _, context = order(
      'framed',
      'data=data\ncontent=Empty.esp\ncontent=Headless.esp\n',
      { ['data/Empty.esp'] = '', ['data/Headless.esp'] = fixtures.static 'rock' }
    )
    local opened = loadOrder.open(context)
    expect(opened.failures).toEqual {}
    expect(opened.plugins[1].plugin:count()).toBe(0)
    expect(tags(opened.plugins[2].plugin)).toEqual { 'STAT' }
    -- A file without a TES3 header has no master list to read.
    expect(function() loadOrder.masters(opened.plugins[2].plugin, {}) end).toThrow 'TES3'
  end)

  suite.it('opens the entries given, in the order given', function()
    local directory, context = order(
      'entries',
      'data=data\ncontent=Base.esm\ncontent=Addon.esp\n',
      { ['data/Base.esm'] = Base, ['data/Addon.esp'] = Addon, ['data/Loose.esp'] = Addon }
    )
    local content = context:content()
    local reversed = loadOrder.open(context, { entries = { content[2], content[1] } })
    expect(names(reversed.plugins)).toEqual { 'Addon.esp', 'Base.esm' }

    -- A file that isn't in the content list opens from the path the Context resolves it to.
    local loose = loadOrder.open(context, {
      entries = {
        { name = 'Loose.esp', path = context:resolve 'loose.esp' },
        { name = 'Nowhere.esp', path = context:resolve 'Nowhere.esp' },
      },
    })
    expect(loose.plugins[1].path).toBe(jess.fs.join(directory, 'data/Loose.esp'))
    expect(loose.failures).toEqual {
      { name = 'Nowhere.esp', problem = 'no data folder has \'Nowhere.esp\'' },
    }

    -- Given entries are opened as they are: nothing is left out for its name.
    local scripts = loadOrder.open(context, {
      entries = { { name = 'Scripts.omwscripts', path = jess.fs.join(directory, 'data/Base.esm') } },
    })
    expect(names(scripts.plugins)).toEqual { 'Scripts.omwscripts' }
    expect(loadOrder.open(context, { entries = {} })).toEqual {
      encoding = 'win1252',
      plugins = {},
      failures = {},
    }
  end)

  suite.it('reads text in the configuration\'s code page', function()
    -- "Факел" in Windows-1251, which Windows-1252 reads as "Ôàêåë".
    local torch = '\xD4\xE0\xEA\xE5\xEB'
    local files = { ['data/Russian.esp'] = fixtures.plugin { fixtures.light(torch) } }
    local _, russian = order('encoding', 'data=data\nencoding=win1251\ncontent=Russian.esp\n', files)
    local opened = loadOrder.open(russian)
    expect(opened.encoding).toBe 'win1251'
    expect(opened.plugins[1].plugin.encoding).toBe 'win1251'
    expect(tes3.records.id(opened.plugins[1].plugin, 1)).toBe 'Факел'
    expect((opened.plugins[1].plugin:decode(1) :: tes3.Value).id).toBe 'Факел'

    local _, western = order('encoding-default', 'data=data\ncontent=Russian.esp\n', files)
    expect(loadOrder.open(western).encoding).toBe 'win1252'
    expect(tes3.records.id(loadOrder.open(western).plugins[1].plugin, 1)).toBe 'Ôàêåë'

    -- An encoding asked for outranks the configuration's.
    local asked = loadOrder.open(western, { encoding = 'win1251' })
    expect(tes3.records.id(asked.plugins[1].plugin, 1)).toBe 'Факел'
    expect(tes3.records.id(loadOrder.open(russian, { encoding = 'win1250' }).plugins[1].plugin, 1)).toBe 'Ôŕęĺë'
    expect(function() loadOrder.open(western, { encoding = 'utf8' }) end).toThrow 'unknown encoding \'utf8\': expected win1250, win1251, or win1252'
  end)

  suite.it('keeps only the record types and CELL parts asked for', function()
    local world = fixtures.plugin {
      fixtures.static 'rock',
      fixtures.cell 'Cave',
      fixtures.light 'torch',
      fixtures.record('NPC_', fixtures.subrecord('NAME', 'guard\0')),
    }
    local _, context = order('types', 'data=data\ncontent=World.esm\n', { ['data/World.esm'] = world })

    local lights = loadOrder.open(context, { types = { 'LIGH' } }).plugins[1].plugin
    expect(tags(lights)).toEqual { 'TES3', 'LIGH' }
    expect(tags(loadOrder.open(context, { types = { 'Light', 'npc', 'cell' } }).plugins[1].plugin)).toEqual {
      'TES3',
      'CELL',
      'LIGH',
      'NPC_',
    }

    expect(tags(loadOrder.open(context, { types = {} }).plugins[1].plugin)).toEqual { 'TES3' }
    expect(loadOrder.open(context, { types = {} }).plugins[1].size).toBe(#world)

    -- A cell read without its references is its header: the name and the data.
    local headers = loadOrder.open(context, { cell = { references = false } }).plugins[1].plugin
    expect(tags(headers)).toEqual { 'TES3', 'STAT', 'CELL', 'LIGH', 'NPC_' }
    expect(headers:keptParts(2)).toEqual { header = true, references = false }
    expect(headers:hasPartialRecords()).toBe(true)
    local cave = headers:decode(2) :: tes3.Value
    expect(cave.name).toBe 'Cave'
    expect(cave.references).toEqual {}

    local both = loadOrder.open(context, { types = { 'CELL' }, cell = { references = false } })
    expect(tags(both.plugins[1].plugin)).toEqual { 'TES3', 'CELL' }
    expect(both.plugins[1].plugin:keptParts(1)).toEqual { header = true, references = false }

    -- Asking for every part is asking for nothing to be left out.
    local whole = loadOrder.open(context, { cell = { header = true } }).plugins[1].plugin
    expect(whole:hasPartialRecords()).toBe(false)
    expect(buffer.tostring(whole:save())).toBe(world)
  end)

  suite.it('refuses options and record types it doesn\'t know', function()
    local _, context = order('options', 'data=data\ncontent=Base.esm\n', { ['data/Base.esm'] = Base })
    -- Each call is the error it is checked to raise.
    expect(function() loadOrder.open(context, { decode = true } :: any) end).toThrow 'load-order: unknown open option \'decode\': expected cell, encoding, entries, or types'
    expect(function() loadOrder.open(context, { types = { 'Lights' } }) end).toThrow 'load-order: invalid record type \'Lights\': expected a tag like LIGH or a type name like Light'
  end)
end)

suite.describe('masters', function()
  suite.it('finds each master in a load order, or says it isn\'t there', function()
    local patch = fixtures.plugin({}, {
      { name = 'BASE.ESM', size = 7 },
      { name = 'Gone.esm', size = 1234 },
      { name = 'Late.esp', size = 2 ^ 33 },
    })
    local _, context = order(
      'masters',
      'data=data\ncontent=Base.esm\ncontent=Patch.esp\ncontent=Missing.esp\ncontent=Late.esp\n',
      { ['data/Base.esm'] = Base, ['data/Patch.esp'] = patch, ['data/Late.esp'] = Addon }
    )
    local opened = loadOrder.open(context)
    expect(names(opened.plugins)).toEqual { 'Base.esm', 'Patch.esp', 'Late.esp' }

    -- Among the files that opened: the absent master has no position, and Late.esp loads after
    -- the plugin that needs it.
    expect(loadOrder.masters(opened.plugins[2].plugin, names(opened.plugins))).toEqual {
      { name = 'BASE.ESM', size = 7, position = 1 },
      { name = 'Gone.esm', size = 1234 },
      { name = 'Late.esp', size = 8589934592, position = 3 },
    }

    -- Among everything the configuration lists, a file that didn't open still has its place.
    local listed = {}
    for _, entry in context:content() do
      table.insert(listed, entry.name)
    end

    expect(loadOrder.masters(opened.plugins[2].plugin, listed)[3].position).toBe(4)
    expect(loadOrder.masters(opened.plugins[3].plugin, listed)).toEqual {
      { name = 'Base.esm', size = #Base, position = 1 },
    }

    expect(loadOrder.masters(opened.plugins[1].plugin, listed)).toEqual {}
    expect(loadOrder.masters(opened.plugins[3].plugin, {})).toEqual {
      { name = 'Base.esm', size = #Base },
    }

    -- A name listed twice counts where it's listed last.
    expect(loadOrder.masters(opened.plugins[3].plugin, { 'base.esm', 'Other.esp', 'Base.esm' })[1].position).toBe(3)
  end)
end)

suite.describe('output', function()
  suite.it('writes to data-local when the configuration has one', function()
    local directory, context = order('output-local', 'data=data\ndata-local=local\n')
    expect(loadOrder.outputDirectory(context)).toBe(jess.fs.join(directory, 'local'))
  end)

  suite.it('writes to the first data folder without a data-local', function()
    local directory, context = order('output-data', 'data=first\ndata=second\n')
    expect(loadOrder.outputDirectory(context)).toBe(jess.fs.join(directory, 'first'))
  end)

  suite.it('never writes to the engine\'s own data folder', function()
    local directory, context =
      order('output-engine', 'resources=resources\ndata=resources/vfs\ndata=mods\n')
    expect(loadOrder.outputDirectory(context)).toBe(jess.fs.join(directory, 'mods'))

    local _, engineOnly = order('output-engine-only', 'resources=resources\ndata=resources/vfs\n')
    expect(loadOrder.outputDirectory(engineOnly)).toBeNil()
  end)

  suite.it('has nowhere to write without a data folder', function()
    local _, context = order('output-none', 'content=Base.esm\n')
    expect(loadOrder.outputDirectory(context)).toBeNil()
  end)
end)

suite.describe('activation', function()
  suite.it('adds a plugin in the data folders to the content, once', function()
    local directory, context = order(
      'activate',
      'data=data\ndata-local=local\ncontent=Base.esm\n',
      { ['data/Base.esm'] = Base }
    )

    -- A tool writes its plugin where `outputDirectory` says, then activates it.
    local output = loadOrder.outputDirectory(context) :: string
    io(fs.mkdir(output, { recursive = true }))
    io(fs.writeFile(jess.fs.join(output, 'Generated.omwaddon'), Addon))

    expect({ loadOrder.activate(context, 'Generated.omwaddon') }).toEqual { true }
    expect({ loadOrder.activate(context, 'generated.OMWADDON') }).toEqual { false }
    expect({ loadOrder.activate(context, 'base.esm') }).toEqual { false }
    expect(names(loadOrder.open(context).plugins)).toEqual { 'Base.esm', 'Generated.omwaddon' }

    -- Nothing is written until the Context saves, which backs the configuration up first.
    local path = jess.fs.join(directory, 'openmw.cfg')
    expect(io(fs.readFileString(path))).toBe 'data=data\ndata-local=local\ncontent=Base.esm\n'
    local written = context:save()
    expect(written.path).toBe(path)
    expect(io(fs.readFileString(written.backup :: string))).toBe 'data=data\ndata-local=local\ncontent=Base.esm\n'
    expect(openmw.new(path):configuration():values 'content').toEqual { 'Base.esm', 'Generated.omwaddon' }
  end)

  suite.it('says why a plugin outside the data folders stays out', function()
    local directory, context = order('activate-elsewhere', 'data=data\ncontent=Base.esm\n', {
      ['data/Base.esm'] = Base,
      ['elsewhere/Generated.omwaddon'] = Addon,
    })
    local added, reason = loadOrder.activate(context, 'Generated.omwaddon')
    expect(added).toBeNil()
    expect(reason).toContain '\'Generated.omwaddon\' isn\'t in the data folders'
    expect(context:configuration():values 'content').toEqual { 'Base.esm' }
    expect(jess.fs.isFile(jess.fs.join(directory, 'elsewhere/Generated.omwaddon'))).toBe(true)

    -- A name openmw.cfg can't spell is refused the same way.
    local unspelled, why = loadOrder.activate(context, 'Two\nLines.esp')
    expect(unspelled).toBeNil()
    expect(type(why)).toBe 'string'
  end)
end)

return suite
