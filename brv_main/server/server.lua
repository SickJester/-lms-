RegisterServerEvent('brv:playerSpawned')
RegisterServerEvent('brv:saveCoords')
RegisterServerEvent('brv:playerLoaded')
RegisterServerEvent('brv:playerDied')
RegisterServerEvent('brv:skinChanged')
RegisterServerEvent('brv:saveSkin')
RegisterServerEvent('brv:vote')
RegisterServerEvent('brv:showScoreboard')
RegisterServerEvent('brv:startGame')
RegisterServerEvent('brv:stopGame')
RegisterServerEvent('brv:stopGameClients')
RegisterServerEvent('brv:clientGameStarted')
RegisterServerEvent('baseevents:onPlayerDied')
RegisterServerEvent('baseevents:onPlayerKilled')


local players = { }
local alivePlayersCount = 0

local isGameStarted = false
local gameId = 0
local safeZonesCoords = { }

local sqlDateFormat = '%Y-%m-%d %H:%M:%S'


function getIsGameStarted()
  return isGameStarted
end


local function isPlayerBanned(player)
  return player.status == 0
end

function getPlayers()
  return players
end


function getPlayer(source)
  return players[source]
end


function getPlayerName(source)
  return players[source].name
end


function getAlivePlayers()
  local alivePlayers = { }
  local index = 1

  for _, player in ipairs(players) do
    if player.alive then
      alivePlayers[index] = player
      index = index +1
    end
  end

  return alivePlayers
end


function getVotes()
  local votes = 0
  for _, player in ipairs(players) do
    if player.voted then
      votes = votes + 1
    end
  end

  return votes
end


function vote(source)
  if players[source] then
    players[source].voted = true
  end
end


local function loadPlayer(source)
  if players[source] == nil then
    local steamId = GetPlayerIdentifiers(source)[1]

    MySQL.Async.fetchAll('SELECT * FROM players WHERE steamid=@steamid LIMIT 1', {['@steamid'] = steamId}, function(playerData)
      local player = playerData[1]

      if player then
        if isPlayerBanned(player) then
          DropPlayer(source, 'You are permanently banned from this server.')
          return
        end

        players[source] = Player.new(player.id, steamId, player.name, player.role, player.skin, source) 
        MySQL.Async.execute('UPDATE players SET last_login=@last_login WHERE id=@id', {['@last_login'] = os.date(sqlDateFormat), ['@id'] = player.id})
        TriggerEvent('brv:playerLoaded', source, players[source])
      else
          local playerName = GetPlayerName(source)
          local playerRole = 'player'

          MySQL.Async.execute('INSERT INTO players (steamid, role, name, created, last_login, status) VALUES (@steamid, @role, @name, @created, @last_login, @status)',
            {['@steamid'] = steamId, ['@role'] = playerRole, ['@name'] = playerName, ['@created'] = os.date(sqlDateFormat), ['@last_login'] = os.date(sqlDateFormat), 
              ['@status'] = 1}, function()
                MySQL.Async.fetchScalar('SELECT id FROM players WHERE steamid=@steamid', {['@steamid'] = steamId}, function(id)
                  players[source] = Player.new(id, steamId, playerName, playerRole, nil, source)
                  TriggerEvent('brv:playerLoaded', source, players[source])
                end)
          end)
      end
    end)
  end
end


function removePlayer(source, reason)
  if players[source] then
    if isGameStarted and players[source].alive then
      players[source].alive = false
      alivePlayersCount = alivePlayersCount - 1

      TriggerClientEvent('brv:updateAlivePlayers', -1, getAlivePlayers())

      if alivePlayersCount == 1 then
        TriggerEvent('brv:stopGame', true, false)
      end
    end

    sendSystemMessage(-1, players[source].name ..' left (' .. reason .. ')')

    players[source] = nil

    local playersCount = count(getPlayers())
    TriggerClientEvent('brv:updateRemainingToStartPlayers', -1, math.max(conf.autostart - playersCount, 0))

    if playersCount == 0 then
      if isGameStarted then
          TriggerEvent('brv:stopGame', false, true)
      end
    end
  end
end


Citizen.CreateThread(function()
  math.randomseed(os.time())
end)


AddEventHandler('brv:playerSpawned', function()
  if not players[source] then
      loadPlayer(source)
  end
end)

AddEventHandler('brv:saveCoords', function(coords)
  MySQL.Async.execute('INSERT INTO coords (x, y, z) VALUES (@x, @y, @z)', {['@x'] = coords.x, ['@y'] = coords.y, ['@z'] = coords.z})
end)

AddEventHandler('brv:getPlayerData', function(source, event, data)
  if players[source] ~= nil then
    local playerData = {
      id = players[source].id,
      name = players[source].name,
      source = players[source].source,
      rank = players[source].rank,
      kills = players[source].kills,
      skin = players[source].skin,
      admin = players[source]:isAdmin(),
    }
    TriggerEvent(event, playerData, data)
  end
end)

AddEventHandler('brv:showScoreboard', function()
  local playersData = { }
  for _, player in ipairs(players) do
    table.insert(playersData, { name = player.name, source = player.source, rank = player.rank, kills = player.kills, admin = player:isAdmin() })
  end

  MySQL.Async.fetchAll('SELECT players.name, SUM(players_stats.kills) AS \'kills\', COUNT(players_stats.gid) AS \'games\', game_stats.wins FROM players, players_stats, ( SELECT players.id AS id, COUNT(games.wid) AS wins FROM players, games WHERE players.id = games.wid GROUP BY players.id) AS game_stats WHERE players.id = players_stats.pid AND players.id = game_stats.id GROUP BY players.id ORDER BY wins DESC, kills DESC, games DESC LIMIT 10;', { }, function(globalData)
    TriggerClientEvent('brv:showScoreboard', source, {players = playersData, global = globalData})
      end)
end)

AddEventHandler('brv:playerLoaded', function(source, player)
  TriggerClientEvent('brv:playerLoaded', source, {id = player.id, name = player.name, skin = player.skin, source = player.source})

  local playersCount = count(getPlayers())
  TriggerClientEvent('brv:updateRemainingToStartPlayers', -1, math.max(conf.autostart - playersCount, 0))

  sendSystemMessage(-1, player.name .. ' connected.')

  TriggerEvent('chatMessage', source, player.name, '/help')

  if not isGameStarted then
    if playersCount == conf.autostart then
      TriggerClientEvent('brv:restartGame', -1)
    end
  else
    TriggerClientEvent('brv:updateAlivePlayers', source, getAlivePlayers())
    TriggerClientEvent('brv:setGameStarted', source)
  end

end)

AddEventHandler('brv:skinChanged', function(newSkin)
  local player = getPlayer(source)
  if player then player.skin = newSkin end
end)

AddEventHandler('brv:saveSkin', function(source)
  local player = getPlayer(source)
  if player then
    MySQL.Async.execute('UPDATE players SET skin=@skin WHERE id=@id', {['@skin'] = player.skin, ['@id'] = player.id}, function()
      sendSystemMessage(player.source, 'Skin saved (^4' .. player.skin .. '^2)')
    end)
  end
end)

AddEventHandler('brv:vote', function()
  TriggerEvent('brv:voteServer', source)
end)

AddEventHandler('brv:voteServer', function(source)
  local player = getPlayer(source)
  if player then
    if player.voted then
      sendSystemMessage(player.source, 'You already voted')
    elseif isGameStarted then
      sendSystemMessage(player.source, 'You can\'t vote during the match')
    else
      vote(player.source)

      sendSystemMessage(-1, '^5' .. player.name .. '^2 voted for the match to begin')

      local playersCount = count(getPlayers())
      if playersCount > 1 and getVotes() > math.floor(playersCount / 2) then
        sendSystemMessage(-1, '^0Voting is over, the match will begin soon...')
        TriggerClientEvent('brv:restartGame', -1)
      end
    end
  end
end)


-- REFACTOR ME
AddEventHandler('brv:startGame', function()
  if isGameStarted then return end

  isGameStarted = true

  -- Generate first (smallest) safe zone
  local randomLocation = getRandomLocation()
  safeZonesCoords = {
    {
      x = randomLocation.x,
      y = randomLocation.y,
      z = randomLocation.z,
      radius = conf.safeZoneRadiuses[1]
    }
  }

  -- Generate other safe zones
  local previousRadius = nil
  for i = 1, count(conf.safeZoneRadiuses) - 1 do
    previousRadius = conf.safeZoneRadiuses[i]

    safeZonesCoords[i + 1] = {
      x = safeZonesCoords[i].x + (math.random(previousRadius - (20 * i)) * (round(math.random()) * 2 - 1)),
      y = safeZonesCoords[i].y + (math.random(previousRadius - (20 * i)) * (round(math.random()) * 2 - 1)),
      z = safeZonesCoords[i].z,
      radius = conf.safeZoneRadiuses[i + 1],
    }
  end

  -- Limit biggest safe zone by map size
  safeZonesCoords[count(conf.safeZoneRadiuses)] = limitMap(safeZonesCoords[count(conf.safeZoneRadiuses)])

  -- Reverse safe zones
  safeZonesCoords = table_reverse(safeZonesCoords)

  -- Sets all players alive, and init some other variables
  alivePlayersCount = count(players)
  for i, player in pairs(players) do
    player.alive = true
    player.rank = 0
    player.kills = 0
    player.spawn = {}
    player.weapon = ''
    player.voted = false
  end

  -- Insert data in DB
  safeZonesJSON = json.encode(safeZonesCoords)

  MySQL.Async.execute('INSERT INTO games (safezones, created) VALUES (@safezones, @created)', {['@safezones'] = safeZonesJSON, ['@created'] = os.date(sqlDateFormat)}, function()
    MySQL.Async.fetchScalar('SELECT MAX(id) FROM games', { }, function(id) --TODO Ugly stuff
      gameId = id --UNSAFE
    end)
  end)

  TriggerClientEvent('brv:startGame', -1, alivePlayersCount, safeZonesCoords)

  -- Create pickups
  local pickupIndexes = { }
  local pickupCount = count(pickupItems)

  for i = 1, count(locations) do
    table.insert(pickupIndexes, math.random(pickupCount))
  end

  TriggerClientEvent('brv:createPickups', -1, pickupIndexes)
end)


AddEventHandler('brv:clientGameStarted', function(stats)
  if players[source] ~= nil then
    players[source].spawn = stats.spawn
    players[source].weapon = stats.weapon
  end
end)


-- REFACTOR ME
AddEventHandler('brv:stopGame', function(restart, noWin)
  TriggerClientEvent('brv:updateRemainingToStartPlayers', -1, math.max(conf.autostart - count(players), 0))

  if count(players) < conf.autostart then restart = false end

  if not isGameStarted then
    TriggerClientEvent('brv:stopGame', -1, nil, restart)
    return false
  end


  local alivePlayers = getAlivePlayers()
  local winner = { id = nil, name = nil }
  if not noWin and count(alivePlayers) == 1 then
    winner = alivePlayers[1]
    winner.rank = 1
  end
  if conf.stats then
    for k,player in pairs(players) do
      if player.weapon ~= '' then
        MySQL.Async.execute('INSERT INTO players_stats (pid, gid, spawn, weapon, kills, rank) VALUES (@pid, @gid, @spawn, @weapon, @kills, @rank)',
          {['@pid'] = player.id, ['@gid'] = gameId, ['@spawn'] = json.encode(player.spawn), ['@weapon'] = player.weapon, ['@kills'] = player.kills, ['@rank'] = player.rank})
      end
    end
  end

  -- Update database
  isGameStarted = false
  MySQL.Async.execute('UPDATE games SET finished=@finished, wid=@wid WHERE id=@id', {['@finished'] = os.date(sqlDateFormat), ['@wid'] = winner.id, ['@id'] = gameId}, function()
    if winner.id then
      TriggerClientEvent('brv:winnerScreen', winner.source, winner.rank, winner.kills, restart)
    else
      TriggerClientEvent('brv:stopGame', -1, winner.name, restart)
    end
  end)
end)


AddEventHandler('brv:stopGameClients', function(name, restart)
  TriggerClientEvent('brv:stopGame', -1, name, restart)
end)

-- REFACTOR ME
AddEventHandler('brv:playerDied', function(source, killer, suicide)
  players[source].rank = alivePlayersCount;

  TriggerClientEvent('brv:wastedScreen', source, players[source].rank, players[source].kills)

  alivePlayersCount = alivePlayersCount - 1

  players[source].alive = false

  TriggerClientEvent('brv:updateAlivePlayers', -1, getAlivePlayers())

  local message = ''
  local playerName = '~o~<C>'..getPlayerName(source)..'</C>~w~'

  if suicide then
    message = playerName..' commited suicide.'
  elseif killer then
    local killerName = '~o~<C>'..getPlayerName(killer)..'</C>~w~'
    message = killerName..' '..getKilledMessage()..' '..playerName
  else
    message = playerName..' died.'
  end

  sendNotification(-1, message)

  if not conf.debug and isGameStarted and alivePlayersCount == 1 and count(players) > 1 then
    TriggerEvent('brv:stopGame', true, false)
  end
end)

-- THIS DOESN'T WORK
AddEventHandler('brv:sendToDiscord', function(name, message)
  if conf.discord_url == nil or conf.discord_url == '' then return false end

  PerformHttpRequest(conf.discord_url, function(err, text, headers) end, 'POST', json.encode({username = name, content = message}), { ['Content-Type'] = 'application/json' })
end)


AddEventHandler('playerDropped', function(reason)
  removePlayer(source, reason)
end)


AddEventHandler('baseevents:onPlayerDied', function()
  TriggerEvent('brv:playerDied', source, nil, true)
end)


AddEventHandler('baseevents:onPlayerKilled', function(killer)
  if killer ~= -1 then
    TriggerEvent('brv:playerDied', source, killer)
  else
    TriggerEvent('brv:playerDied', source)
  end

  if players[killer] then
    players[killer].kills = players[killer].kills + 1;
  end
end)
