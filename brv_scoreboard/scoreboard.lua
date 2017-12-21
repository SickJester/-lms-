local displayingScoreboard = false
local scoreboardButton = { group = 0, id = 27} --[[ INPUT_PHONE ]]
local currentPlayersLimit = 20
local globalRankingLimit = 10


local function isDisplayingScoreboard()
  return displayingScoreboard
end


local function hideScoreboard()
  displayingScoreboard = false
  SendNUIMessage( { meta = 'close' } )
end


local function requestScoreboard()
  displayingScoreboard = true
  TriggerServerEvent('brv:showScoreboard')
end


local function sortPlayers(lhs, rhs)
  if not lhs.rank then return false end
  if not rhs.rank then return true end

  if lhs.rank > rhs.rank then return false end
  if lhs.rank < rhs.rank then return true end

  if not lhs.kills then return true end
  if not rhs.kills then return false end

  if lhs.kills > rhs.kills then return true end
  if lhs.kills < rhs.kills then return false end

  return lhs.name < rhs.name
end


Citizen.CreateThread(function()
  while true do
    Citizen.Wait(0)

    if IsControlPressed(scoreboardButton.group, scoreboardButton.id) then
      if not isDisplayingScoreboard() then
        requestScoreboard()
      end
    end
  end
end)


RegisterNetEvent('brv:showScoreboard')
AddEventHandler('brv:showScoreboard', function(data)
  Citizen.CreateThread(function()
    displayingScoreboard = false
    if IsControlPressed(scoreboardButton.group, scoreboardButton.id) then
      local currentPlayers = data.players
      table.sort(currentPlayers, sortPlayers)

      local currentPlayersStats = { }
      for i = 1, math.min(currentPlayersLimit, #currentPlayers) do
        if not currentPlayers[i].kills then currentPlayers[i].kills = 'N/A' end
        if not currentPlayers[i].rank then currentPlayers[i].rank = 'N/A' end

        table.insert(currentPlayersStats, '<tr class=""><td>' .. currentPlayers[i].source .. '</td><td>' .. currentPlayers[i].name .. '</td><td>' .. currentPlayers[i].kills .. '</td><td>' .. currentPlayers[i].rank .. '</td></tr>')
      end



      local globalRankingStats = { } -- we don't need to sort it because of getting from DB already sorted
      for i = 1, math.min(globalRankingLimit, #data.global) do
        table.insert(globalRankingStats, '<tr class=""><td>' .. data.global[i].name .. '</td><td>' .. data.global[i].wins .. '</td><td>' .. data.global[i].kills .. '</td><td>' .. data.global[i].games .. '</td></tr>')
      end

      SendNUIMessage( { text = table.concat(currentPlayersStats), global = table.concat(globalRankingStats) } )

      displayingScoreboard = true
      while isDisplayingScoreboard() do
        Citizen.Wait(0)
        if not IsControlPressed(scoreboardButton.group, scoreboardButton.id) then
          hideScoreboard()
          break
        end
      end
    end
  end)
end)
