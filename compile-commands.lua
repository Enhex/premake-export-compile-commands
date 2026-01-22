local p = premake

p.modules.export_compile_commands = {}
local m = p.modules.export_compile_commands

local workspace = p.workspace
local project = p.project

function m.getToolset(cfg)
  return p.tools[cfg.toolset or 'gcc']
end

function m.getIncludeDirs(cfg)
  local flags = {}
  for _, dir in ipairs(cfg.includedirs) do
    table.insert(flags, '-I' .. p.quoted(dir))
  end
  for _, dir in ipairs(cfg.sysincludedir or {}) do
    table.insert(result, '-isystem ' .. p.quoted(dir))
  end
  return flags
end

function m.get_forceincludes(cfg)
  local flags = {}
  for _, path in ipairs(cfg.forceincludes) do
    table.insert(flags, '-include ' .. p.quoted(path))
  end
  return flags
end


function m.getCommonFlags(prj, cfg)
  local toolset = m.getToolset(cfg)
  local flags = toolset.getcppflags(cfg)
  flags = table.join(flags, toolset.getdefines(cfg.defines))
  flags = table.join(flags, toolset.getundefines(cfg.undefines))
  -- can't use toolset.getincludedirs because some tools that consume
  -- compile_commands.json have problems with relative include paths
  flags = table.join(flags, m.getIncludeDirs(cfg))
  flags = table.join(flags, m.get_forceincludes(cfg))
  if p.project.isc(prj) then
    flags = table.join(flags, toolset.getcflags(cfg))
  elseif p.project.iscpp(prj) then
    flags = table.join(flags, toolset.getcxxflags(cfg))
  end
  return table.join(flags, cfg.buildoptions)
end

function m.getObjectPath(prj, cfg, node)
  return path.join(cfg.objdir, path.appendExtension(node.objname, '.o'))
end

function m.getDependenciesPath(prj, cfg, node)
  return path.join(cfg.objdir, path.appendExtension(node.objname, '.d'))
end

function m.getFileFlags(prj, cfg, node)
  return table.join(m.getCommonFlags(prj, cfg), {
    '-o', m.getObjectPath(prj, cfg, node),
    '-MF', m.getDependenciesPath(prj, cfg, node),
    '-c', node.abspath
  })
end

function m.generateCompileCommand(prj, cfg, node, filepath)
  return {
    directory = prj.location,
    file = filepath,
    command = 'cc '.. table.concat(m.getFileFlags(prj, cfg, node), ' ')
  }
end

function m.includeFile(node)
  if node.abspath == nil then
    return false
  end
  return path.iscppfile(node.abspath)
end

function m.getConfig(prj)
  if _OPTIONS['compile-commands-config'] then
    return project.getconfig(prj, _OPTIONS['compile-commands-config'],
      _OPTIONS['compile-commands-platform'])
  end
  for cfg in project.eachconfig(prj) do
    -- just use the first configuration which is usually "Debug"
    return cfg
  end
end

function m.getProjectCommands(prj, cfg)
  local cmds = {}
  local tr = project.getsourcetree(prj)
  p.tree.traverse(tr, {
    onleaf = function(node, depth)
      if not m.includeFile(node) then
        return
      end
      table.insert(cmds, m.generateCompileCommand(prj, cfg, node, node.abspath))
    end
  }, true)

  return cmds
end

local function execute()
  for wks in p.global.eachWorkspace() do
    local cfgCmds = {}
    for prj in workspace.eachproject(wks) do
      for cfg in project.eachconfig(prj) do
        local cfgKey = string.format('%s', cfg.shortname)
        if not cfgCmds[cfgKey] then
          cfgCmds[cfgKey] = {}
        end
        cfgCmds[cfgKey] = table.join(cfgCmds[cfgKey], m.getProjectCommands(prj, cfg))
      end
    end
    for cfgKey,cmds in pairs(cfgCmds) do
      local outfile = string.format('compile_commands.json', cfgKey)
      p.generate(wks, outfile, function(wks)
        p.w('[')
        for i = 1, #cmds do
          local item = cmds[i]
          local command = string.format([[
          {
            "directory": "%s",
            "file": "%s",
            "command": "%s"
          }]],
          item.directory,
          item.file,
          item.command:gsub('\\', '\\\\'):gsub('"', '\\"'))
          if i > 1 then
            p.w(',')
          end
          p.w(command)
        end
        p.w(']')
      end)
    end
  end
end

newaction {
  trigger = 'compile-commands',
  description = 'Export compiler commands in JSON Compilation Database Format',
  execute = execute
}

return m
