local Details = _G.Details
local DF = _G.DetailsFramework
local C_Timer = _G.C_Timer
local unpack = _G.unpack
local GetTime = _G.GetTime
local tremove = _G.tremove
local GetInstanceInfo = _G.GetInstanceInfo
local addonName, Details222 = ...

local Loc = _G.LibStub("AceLocale-3.0"):GetLocale("Details")

--data for the current mythic + dungeon
Details.MythicPlus = {
    RunID = 0,
}

-- ~mythic ~dungeon
local DetailsMythicPlusFrame = _G.CreateFrame("frame", "DetailsMythicPlusFrame", UIParent)
DetailsMythicPlusFrame.DevelopmentDebug = false

--disabling the mythic+ feature if the user is playing in wow classic
if (not DF.IsTimewalkWoW()) then
    DetailsMythicPlusFrame:RegisterEvent("CHALLENGE_MODE_START")
    DetailsMythicPlusFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    DetailsMythicPlusFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    DetailsMythicPlusFrame:RegisterEvent("ENCOUNTER_END")
    DetailsMythicPlusFrame:RegisterEvent("START_TIMER")
end

function Details222.MythicPlus.LogStep(log)
    local today = date("%d/%m/%y %H:%M:%S")
    table.insert(Details.mythic_plus_log, 1, today .. "|" .. log)
    tremove(Details.mythic_plus_log, 50)
end


--[[
    all mythic segments have:
        .is_mythic_dungeon_segment = true
        .is_mythic_dungeon_run_id = run id from details.profile.mythic_dungeon_id
    boss, 'trash overall' and 'dungeon overall' segments have:
        .is_mythic_dungeon
    boss segments have:
        .is_boss
    'trash overall' segments have:
        .is_mythic_dungeon with .SegmentID = "trashoverall"
    'dungeon overall' segment have:
        .is_mythic_dungeon with .SegmentID = "overall"

--]]

function DetailsMythicPlusFrame.MergeSegmentsOnEnd() --~merge
    --at the end of a mythic run, if enable on settings, merge all the segments from the mythic run into only one
    if (DetailsMythicPlusFrame.DevelopmentDebug) then
        print("Details!", "MergeSegmentsOnEnd() > starting to merge mythic segments.", "InCombatLockdown():", InCombatLockdown())
    end

    Details222.MythicPlus.LogStep("MergeSegmentsOnEnd started | creating the overall segment at the end of the run.")

    --create a new combat to be the overall for the mythic run
    Details:StartCombat()

    --get the current combat just created and the table with all past segments
    local newCombat = Details:GetCurrentCombat()
    local segmentsTable = Details:GetCombatSegments()

    local timeInCombat = 0
    local startDate, endDate = "", ""
    local lastSegment
    local totalSegments = 0

    --copy deaths occured on all segments to the new segment, also sum the activity combat time
    if (Details.mythic_plus.reverse_death_log) then
        for i = 1, 40 do --copy the deaths from the first segment to the last one
            local thisCombat = segmentsTable[i]
            if (thisCombat and thisCombat.is_mythic_dungeon_run_id == Details.mythic_dungeon_id) then
                newCombat:CopyDeathsFrom(thisCombat, true)
                timeInCombat = timeInCombat + thisCombat:GetCombatTime()
            end
        end
    else
        for i = 40, 1, -1 do --copy the deaths from the last segment to the new segment
            local thisCombat = segmentsTable[i]
            if (thisCombat) then
                if (thisCombat.is_mythic_dungeon_run_id == Details.mythic_dungeon_id) then
                    newCombat:CopyDeathsFrom(thisCombat, true)
                    timeInCombat = timeInCombat + thisCombat:GetCombatTime()
                end
            end
        end
    end

    local zoneName, instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceMapID, instanceGroupSize = GetInstanceInfo()

    --tag the segment as mythic overall segment
    newCombat.is_mythic_dungeon = {
        StartedAt = Details.MythicPlus.StartedAt, --the start of the run
        EndedAt = Details.MythicPlus.EndedAt, --the end of the run
        WorldStateTimerStart = Details222.MythicPlus.WorldStateTimerStartAt,
        WorldStateTimerEnd = Details222.MythicPlus.WorldStateTimerEndAt,
        TimeInCombat = timeInCombat,
        SegmentID = "overall", --segment number within the dungeon
        RunID = Details.mythic_dungeon_id,
        OverallSegment = true,
        ZoneName = Details.MythicPlus.DungeonName,
        MapID = instanceMapID,
        Level = Details.MythicPlus.Level,
        EJID = Details.MythicPlus.ejID,
    }

    --add all boss segments from this run to this new segment
    for i = 1, 40 do --from the newer combat to the oldest
        local thisCombat = segmentsTable[i]
        if (thisCombat and thisCombat.is_mythic_dungeon_run_id == Details.mythic_dungeon_id) then
            local canAddThisSegment = true
            if (Details.mythic_plus.make_overall_boss_only) then
                if (not thisCombat.is_boss) then
                    --canAddThisSegment = false --disabled
                end
            end

            if (canAddThisSegment) then
                newCombat = newCombat + thisCombat
                totalSegments = totalSegments + 1

                if (DetailsMythicPlusFrame.DevelopmentDebug) then
                    print("MergeSegmentsOnEnd() > adding time:", thisCombat:GetCombatTime(), thisCombat.is_boss and thisCombat.is_boss.name)
                end

                if (endDate == "") then
                    local _, whenEnded = thisCombat:GetDate()
                    endDate = whenEnded
                end
                lastSegment = thisCombat
            end
        end
    end

    --get the date where the first segment started
    if (lastSegment) then
        startDate = lastSegment:GetDate()
    end

    if (DetailsMythicPlusFrame.DevelopmentDebug) then
        print("Details!", "MergeSegmentsOnEnd() > totalTime:", timeInCombat, "startDate:", startDate)
    end

    newCombat.total_segments_added = totalSegments
    newCombat.is_mythic_dungeon_segment = true
    newCombat.is_mythic_dungeon_run_id = Details.mythic_dungeon_id

    --check if both values are valid, this can get invalid if the player leaves the dungeon before the timer ends or the game crashes
    if (type(Details222.MythicPlus.time) == "number") then
        newCombat.run_time = Details222.MythicPlus.time
        Details222.MythicPlus.LogStep("GetCompletionInfo() Found, Time: " .. Details222.MythicPlus.time)

    elseif (newCombat.is_mythic_dungeon.WorldStateTimerEnd and newCombat.is_mythic_dungeon.WorldStateTimerStart) then
        local runTime = newCombat.is_mythic_dungeon.WorldStateTimerEnd - newCombat.is_mythic_dungeon.WorldStateTimerStart
        newCombat.run_time = Details222.MythicPlus.time
        Details222.MythicPlus.LogStep("World State Timers is Available, Run Time: " .. runTime .. "| start:" .. newCombat.is_mythic_dungeon.WorldStateTimerStart .. "| end:" .. newCombat.is_mythic_dungeon.WorldStateTimerEnd)
    else
        newCombat.run_time = timeInCombat
        Details222.MythicPlus.LogStep("GetCompletionInfo() and World State Timers not Found, Activity Time: " .. timeInCombat)
    end

    newCombat:SetStartTime(GetTime() - timeInCombat)
    newCombat:SetEndTime(GetTime())
    Details222.MythicPlus.LogStep("Activity Time: " .. timeInCombat)

    --set the segment time and date
    newCombat:SetDate(startDate, endDate)

    --immediatly finishes the segment just started
    Details:SairDoCombate()

    --update all windows
    Details:InstanceCallDetailsFunc(Details.FadeHandler.Fader, "IN", nil, "barras")
    Details:InstanceCallDetailsFunc(Details.UpdateCombatObjectInUse)
    Details:InstanceCallDetailsFunc(Details.AtualizaSoloMode_AfertReset)
    Details:InstanceCallDetailsFunc(Details.ResetaGump)
    Details:RefreshMainWindow(-1, true)

    if (DetailsMythicPlusFrame.DevelopmentDebug) then
        print("Details!", "MergeSegmentsOnEnd() > finished merging segments.")
        print("Details!", "MergeSegmentsOnEnd() > all done, check in the segments list if everything is correct, if something is weird: '/details feedback' thanks in advance!")
    end

    local lower_instance = Details:GetLowerInstanceNumber()
    if (lower_instance) then
        local instance = Details:GetInstance(lower_instance)
        if (instance) then
            local func = {function() end}
            instance:InstanceAlert ("Showing Mythic+ Run Segment", {[[Interface\AddOns\Details\images\icons]], 16, 16, false, 434/512, 466/512, 243/512, 273/512}, 6, func, true)
        end
    end
end

--after each boss fight, if enalbed on settings, create an extra segment with all trash segments from the boss just killed
function DetailsMythicPlusFrame.MergeTrashCleanup (isFromSchedule)
    if (DetailsMythicPlusFrame.DevelopmentDebug) then
        print("Details!", "MergeTrashCleanup() > running", DetailsMythicPlusFrame.TrashMergeScheduled and #DetailsMythicPlusFrame.TrashMergeScheduled)
    end

    local segmentsToMerge = DetailsMythicPlusFrame.TrashMergeScheduled

    --table exists and there's at least one segment
    if (segmentsToMerge and segmentsToMerge[1]) then
        Details222.MythicPlus.LogStep("MergeTrashCleanup started.")

        --the first segment is the segment where all other trash segments will be added
        local masterSegment = segmentsToMerge[1]
        masterSegment.is_mythic_dungeon_trash = nil

        --get the current combat just created and the table with all past segments
        local newCombat = masterSegment
        local totalTime = newCombat:GetCombatTime()
        local startDate, endDate = "", ""
        local lastSegment

        --add segments
        for i = 2, #segmentsToMerge do --segment #1 is the host
            local pastCombat = segmentsToMerge[i]
            newCombat = newCombat + pastCombat
            totalTime = totalTime + pastCombat:GetCombatTime()

            newCombat:CopyDeathsFrom(pastCombat, true)

            --tag this combat as already added to a boss trash overall
            pastCombat._trashoverallalreadyadded = true

            if (endDate == "") then
                local _, whenEnded = pastCombat:GetDate()
                endDate = whenEnded
            end
            lastSegment = pastCombat
        end

        --get the date where the first segment started
        if (lastSegment) then
            startDate = lastSegment:GetDate()
        end

        local zoneName, instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceMapID, instanceGroupSize = GetInstanceInfo()

        --tag the segment as mythic overall segment
        newCombat.is_mythic_dungeon = {
            StartedAt = segmentsToMerge.PreviousBossKilledAt, --start of the mythic run or when the previous boss got killed
            EndedAt = segmentsToMerge.LastBossKilledAt, --the time() when encounter_end got triggered
            SegmentID = "trashoverall",
            RunID = Details.mythic_dungeon_id,
            TrashOverallSegment = true,
            ZoneName = Details.MythicPlus.DungeonName,
            MapID = instanceMapID,
            Level = Details.MythicPlus.Level,
            EJID = Details.MythicPlus.ejID,
            EncounterID = segmentsToMerge.EncounterID,
            EncounterName = segmentsToMerge.EncounterName or Loc ["STRING_UNKNOW"],
        }

        newCombat.is_mythic_dungeon_segment = true
        newCombat.is_mythic_dungeon_run_id = Details.mythic_dungeon_id

        --set the segment time / using a sum of combat times, this combat time is reliable
        newCombat:SetStartTime (GetTime() - totalTime)
        newCombat:SetEndTime (GetTime())
        --set the segment date
        newCombat:SetDate (startDate, endDate)

        if (DetailsMythicPlusFrame.DevelopmentDebug) then
            print("Details!", "MergeTrashCleanup() > finished merging trash segments.", Details.tabela_vigente, Details.tabela_vigente.is_boss)
        end

        --delete all segments that were merged
        local segmentsTable = Details:GetCombatSegments()
        for segmentId = #segmentsTable, 1, -1 do
            local segment = segmentsTable[segmentId]
            if (segment and segment._trashoverallalreadyadded) then
                tremove(segmentsTable, segmentId)
            end
        end

        for i = #segmentsToMerge, 1, -1 do
            tremove(segmentsToMerge, i)
        end

        --call the segment removed event to notify third party addons
        Details:SendEvent("DETAILS_DATA_SEGMENTREMOVED")

        --update all windows
        Details:InstanceCallDetailsFunc(Details.FadeHandler.Fader, "IN", nil, "barras")
        Details:InstanceCallDetailsFunc(Details.UpdateCombatObjectInUse)
        Details:InstanceCallDetailsFunc(Details.AtualizaSoloMode_AfertReset)
        Details:InstanceCallDetailsFunc(Details.ResetaGump)
        Details:RefreshMainWindow(-1, true)
    else
        Details222.MythicPlus.LogStep("MergeTrashCleanup | no segments to merge.")
    end
end

--this function merges trash segments after all bosses of the mythic dungeon are defeated
--happens when the group finishes all bosses but don't complete the trash requirement
function DetailsMythicPlusFrame.MergeRemainingTrashAfterAllBossesDone()
    if (DetailsMythicPlusFrame.DevelopmentDebug) then
        print("Details!", "MergeRemainingTrashAfterAllBossesDone() > running, #segments: ", #DetailsMythicPlusFrame.TrashMergeScheduled2, "trash overall table:", DetailsMythicPlusFrame.TrashMergeScheduled2_OverallCombat)
    end

    Details222.MythicPlus.LogStep("running MergeRemainingTrashAfterAllBossesDone.")

    local segmentsToMerge = DetailsMythicPlusFrame.TrashMergeScheduled2
    local overallCombat = DetailsMythicPlusFrame.TrashMergeScheduled2_OverallCombat

    --needs to merge, add the total combat time, set the date end to the date of the first segment
    local totalTime = 0
    local startDate, endDate = "", ""
    local lastSegment

    --add segments
    for i, pastCombat in ipairs(segmentsToMerge) do
        overallCombat = overallCombat + pastCombat
        if (DetailsMythicPlusFrame.DevelopmentDebug) then
            print("MergeRemainingTrashAfterAllBossesDone() >  segment added")
        end
        totalTime = totalTime + pastCombat:GetCombatTime()

        --tag this combat as already added to a boss trash overall
        pastCombat._trashoverallalreadyadded = true

        if (endDate == "") then --get the end date of the first index only
            local _, whenEnded = pastCombat:GetDate()
            endDate = whenEnded
        end
        lastSegment = pastCombat
    end

    --set the segment time / using a sum of combat times, this combat time is reliable
    local startTime = overallCombat:GetStartTime()
    overallCombat:SetStartTime (startTime - totalTime)
    if (DetailsMythicPlusFrame.DevelopmentDebug) then
        print("MergeRemainingTrashAfterAllBossesDone() > total combat time:", totalTime)
    end

    --set the segment date
    local startDate = overallCombat:GetDate()
    overallCombat:SetDate (startDate, endDate)
    if (DetailsMythicPlusFrame.DevelopmentDebug) then
        print("MergeRemainingTrashAfterAllBossesDone() > new end date:", endDate)
    end

    local mythicDungeonInfo = overallCombat:GetMythicDungeonInfo()

    if (DetailsMythicPlusFrame.DevelopmentDebug) then
        print("MergeRemainingTrashAfterAllBossesDone() > elapsed time before:", mythicDungeonInfo.EndedAt - mythicDungeonInfo.StartedAt)
    end
    mythicDungeonInfo.StartedAt = mythicDungeonInfo.StartedAt - (Details.MythicPlus.EndedAt - Details.MythicPlus.PreviousBossKilledAt)
    if (DetailsMythicPlusFrame.DevelopmentDebug) then
        print("MergeRemainingTrashAfterAllBossesDone() > elapsed time after:", mythicDungeonInfo.EndedAt - mythicDungeonInfo.StartedAt)
    end

    --remove trash segments from the segment history after the merge
    local removedCurrentSegment = false
    local segmentsTable = Details:GetCombatSegments()
    for _, pastCombat in ipairs(segmentsToMerge) do
        for i = #segmentsTable, 1, -1 do
            local segment = segmentsTable [i]
            if (segment == pastCombat) then
                --remove the segment
                if (Details.tabela_vigente == segment) then
                    removedCurrentSegment = true
                end
                tremove(segmentsTable, i)
                break
            end
        end
    end

    for i = #segmentsToMerge, 1, -1 do
        tremove(segmentsToMerge, i)
    end

    if (removedCurrentSegment) then
        --find another current segment
        local segmentsTable = Details:GetCombatSegments()
        Details.tabela_vigente = segmentsTable [1]

        if (not Details.tabela_vigente) then
            --assuming there's no segment from the dungeon run
            Details:EntrarEmCombate()
            Details:SairDoCombate()
        end

        --update all windows
        Details:InstanceCallDetailsFunc(Details.FadeHandler.Fader, "IN", nil, "barras")
        Details:InstanceCallDetailsFunc(Details.UpdateCombatObjectInUse)
        Details:InstanceCallDetailsFunc(Details.AtualizaSoloMode_AfertReset)
        Details:InstanceCallDetailsFunc(Details.ResetaGump)
        Details:RefreshMainWindow(-1, true)
    end

    Details222.MythicPlus.LogStep("delete_trash_after_merge | concluded")
    Details:SendEvent("DETAILS_DATA_SEGMENTREMOVED")

    DetailsMythicPlusFrame.TrashMergeScheduled2 = nil
    DetailsMythicPlusFrame.TrashMergeScheduled2_OverallCombat = nil

    if (DetailsMythicPlusFrame.DevelopmentDebug) then
        print("Details!", "MergeRemainingTrashAfterAllBossesDone() > done merging")
    end
end

function DetailsMythicPlusFrame.BossDefeated(this_is_end_end, encounterID, encounterName, difficultyID, raidSize, endStatus) --hold your breath and count to ten
    --this function is called right after defeat a boss inside a mythic dungeon
    --it comes from details! control leave combat
    if (DetailsMythicPlusFrame.DevelopmentDebug) then
        print("Details!", "BossDefeated() > boss defeated | SegmentID:", Details.MythicPlus.SegmentID, " | mapID:", Details.MythicPlus.DungeonID)
    end

    local zoneName, instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceMapID, instanceGroupSize = GetInstanceInfo()

    --add the mythic dungeon info to the combat
    Details.tabela_vigente.is_mythic_dungeon = {
        StartedAt = Details.MythicPlus.StartedAt, --the start of the run
        EndedAt = time(), --when the boss got killed
        SegmentID = Details.MythicPlus.SegmentID, --segment number within the dungeon
        EncounterID = encounterID,
        EncounterName = encounterName or Loc ["STRING_UNKNOW"],
        RunID = Details.mythic_dungeon_id,
        ZoneName = Details.MythicPlus.DungeonName,
        MapID = Details.MythicPlus.DungeonID,
        OverallSegment = false,
        Level = Details.MythicPlus.Level,
        EJID = Details.MythicPlus.ejID,
    }

    local mythicLevel = C_ChallengeMode.GetActiveKeystoneInfo()
    local mPlusTable = Details.tabela_vigente.is_mythic_dungeon
    Details222.MythicPlus.LogStep("BossDefeated | key level: | " .. mythicLevel .. " | " .. (mPlusTable.EncounterName or "") .. " | " .. (mPlusTable.ZoneName or ""))

    --check if need to merge the trash for this boss
    if (Details.mythic_plus.merge_boss_trash and not Details.MythicPlus.IsRestoredState) then
        --store on an table all segments which should be merged
        local segmentsToMerge = DetailsMythicPlusFrame.TrashMergeScheduled or {}

        --table with all past semgnets
        local segmentsTable = Details:GetCombatSegments()

        --iterate among segments
        for i = 1, 25 do --from the newer combat to the oldest
            local pastCombat = segmentsTable [i]
            --does the combat exists
            if (pastCombat and not pastCombat._trashoverallalreadyadded and pastCombat.is_mythic_dungeon_trash) then
                --is the combat a mythic segment from this run?
                local isMythicSegment, SegmentID = pastCombat:IsMythicDungeon()
                if (isMythicSegment and SegmentID == Details.mythic_dungeon_id and not pastCombat.is_boss) then

                    local mythicDungeonInfo = pastCombat:GetMythicDungeonInfo() -- .is_mythic_dungeon only boss, trash overall and run overall have it
                    if (not mythicDungeonInfo or not mythicDungeonInfo.TrashOverallSegment) then
                        --trash segment found, schedule to merge
                        table.insert(segmentsToMerge, pastCombat)
                    end
                end
            end
        end

        --add encounter information
        segmentsToMerge.EncounterID = encounterID
        segmentsToMerge.EncounterName = encounterName
        segmentsToMerge.PreviousBossKilledAt = Details.MythicPlus.PreviousBossKilledAt

        --reduce this boss encounter time from the trash lenght time, since the boss doesn't count towards the time spent cleaning trash
        segmentsToMerge.LastBossKilledAt = time() - Details.tabela_vigente:GetCombatTime()

        DetailsMythicPlusFrame.TrashMergeScheduled = segmentsToMerge

        --there's no more script run too long
        --if (not InCombatLockdown() and not UnitAffectingCombat("player")) then
            if (DetailsMythicPlusFrame.DevelopmentDebug) then
                print("Details!", "BossDefeated() > not in combat, merging trash now")
            end
            --merge the trash clean up
            DetailsMythicPlusFrame.MergeTrashCleanup()
        --else
        --	if (DetailsMythicPlusFrame.DevelopmentDebug) then
        --		print("Details!", "BossDefeated() > player in combatlockdown, scheduling trash merge")
        --	end
        --	_detalhes.schedule_mythicdungeon_trash_merge = true
        --end
    end

    --close the combat
    if (this_is_end_end) then
        --player left the dungeon
        --had some deprecated code removed about alweays in combat
    else
        --increase the segment number for the mythic run
        Details.MythicPlus.SegmentID = Details.MythicPlus.SegmentID + 1

        --register the time when the last boss has been killed (started a clean up for the next trash)
        Details.MythicPlus.PreviousBossKilledAt = time()

        --update the saved table inside the profile
        Details:UpdateState_CurrentMythicDungeonRun (true, Details.MythicPlus.SegmentID, Details.MythicPlus.PreviousBossKilledAt)
    end
end

function DetailsMythicPlusFrame.MythicDungeonFinished (fromZoneLeft)
    if (DetailsMythicPlusFrame.IsDoingMythicDungeon) then
        if (DetailsMythicPlusFrame.DevelopmentDebug) then
            print("Details!", "MythicDungeonFinished() > the dungeon was a Mythic+ and just ended.")
        end

        DetailsMythicPlusFrame.IsDoingMythicDungeon = false
        Details.MythicPlus.Started = false
        Details.MythicPlus.EndedAt = time()-1.9

        Details:UpdateState_CurrentMythicDungeonRun()

        --at this point, details! should not be in combat, but if something triggered a combat start, just close the combat right away
        if (Details.in_combat) then
            if (DetailsMythicPlusFrame.DevelopmentDebug) then
                print("Details!", "MythicDungeonFinished() > was in combat, calling SairDoCombate():", InCombatLockdown())
            end
            Details:SairDoCombate()
            Details222.MythicPlus.LogStep("MythicDungeonFinished() | Details was in combat.")
        end

        local segmentsToMerge = {}

        --check if there is trash segments after the last boss. need to merge these segments with the trash segment of the last boss
        local bCanMergeBossTrash = Details.mythic_plus.merge_boss_trash
        Details222.MythicPlus.LogStep("MythicDungeonFinished() | merge_boss_trash = " .. (bCanMergeBossTrash and "true" or "false"))
        if (bCanMergeBossTrash and not Details.MythicPlus.IsRestoredState and not fromZoneLeft) then
            --is the current combat not a boss fight?
            --this mean a combat was opened after the last boss of the dungeon was killed
            if (not Details.tabela_vigente.is_boss and Details.tabela_vigente:GetCombatTime() > 5) then

                if (DetailsMythicPlusFrame.DevelopmentDebug) then
                    print("Details!", "MythicDungeonFinished() > the last combat isn't a boss fight, might have trash after bosses done.")
                end

                --table with all past semgnets
                local segmentsTable = Details:GetCombatSegments()

                for i = 1, #segmentsTable do
                    local pastCombat = segmentsTable [i]
                    --does the combat exists

                    if (pastCombat and not pastCombat._trashoverallalreadyadded and pastCombat:GetCombatTime() > 5) then
                        --is the last boss?
                        if (pastCombat.is_boss) then
                            break
                        end

                        --is the combat a mythic segment from this run?
                        local isMythicSegment, SegmentID = pastCombat:IsMythicDungeon()
                        if (isMythicSegment and SegmentID == Details.mythic_dungeon_id and pastCombat.is_mythic_dungeon_trash) then

                            --if have mythic dungeon info, cancel the loop
                            local mythicDungeonInfo = pastCombat:GetMythicDungeonInfo()
                            if (mythicDungeonInfo) then
                                break
                            end

                            --merge this segment
                            table.insert(segmentsToMerge, pastCombat)

                            if (DetailsMythicPlusFrame.DevelopmentDebug) then
                                print("MythicDungeonFinished() > found after last boss combat")
                            end
                        end
                    end
                end
            end
        end

        if (#segmentsToMerge > 0) then
            if (DetailsMythicPlusFrame.DevelopmentDebug) then
                print("Details!", "MythicDungeonFinished() > found ", #segmentsToMerge, "segments after the last boss")
            end

            --find the latest trash overall
            local segmentsTable = Details:GetCombatSegments()
            local latestTrashOverall
            for i = 1, #segmentsTable do
                local pastCombat = segmentsTable [i]
                if (pastCombat and pastCombat.is_mythic_dungeon and pastCombat.is_mythic_dungeon.SegmentID == "trashoverall") then
                    latestTrashOverall = pastCombat
                    break
                end
            end

            if (latestTrashOverall) then
                --stores the segment table and the trash overall segment to use on the merge
                DetailsMythicPlusFrame.TrashMergeScheduled2 = segmentsToMerge
                DetailsMythicPlusFrame.TrashMergeScheduled2_OverallCombat = latestTrashOverall

                --there's no more script ran too long
                --if (not InCombatLockdown() and not UnitAffectingCombat("player")) then
                    if (DetailsMythicPlusFrame.DevelopmentDebug) then
                        print("Details!", "MythicDungeonFinished() > not in combat, merging last pack of trash now")
                    end

                    DetailsMythicPlusFrame.MergeRemainingTrashAfterAllBossesDone()
                --else
                --	if (DetailsMythicPlusFrame.DevelopmentDebug) then
                --		print("Details!", "MythicDungeonFinished() > player in combatlockdown, scheduling the merge for last trash packs")
                --	end
                --	_detalhes.schedule_mythicdungeon_endtrash_merge = true
                --end
            end
        end

        --merge segments
        if (Details.mythic_plus.make_overall_when_done and not Details.MythicPlus.IsRestoredState and not fromZoneLeft) then
            --if (not InCombatLockdown() and not UnitAffectingCombat("player")) then
                if (DetailsMythicPlusFrame.DevelopmentDebug) then
                    print("Details!", "MythicDungeonFinished() > not in combat, creating overall segment now")
                end
                DetailsMythicPlusFrame.MergeSegmentsOnEnd()
            --else
            --	if (DetailsMythicPlusFrame.DevelopmentDebug) then
            --		print("Details!", "MythicDungeonFinished() > player in combatlockdown, scheduling the creation of the overall segment")
            --	end
            --	_detalhes.schedule_mythicdungeon_overallrun_merge = true
            --end
        end

        Details.MythicPlus.IsRestoredState = nil

        --shutdown parser for a few seconds to avoid opening new segments after the run ends
        if (not fromZoneLeft) then
            Details:CaptureSet (false, "damage", false, 15)
            Details:CaptureSet (false, "energy", false, 15)
            Details:CaptureSet (false, "aura", false, 15)
            Details:CaptureSet (false, "energy", false, 15)
            Details:CaptureSet (false, "spellcast", false, 15)
        end

        --store data
        --[=[
        local expansion = tostring(select(4, GetBuildInfo())):match ("%d%d")
        if (expansion and type(expansion) == "string" and string.len(expansion) == 2) then
            local expansionDungeonData = _detalhes.dungeon_data [expansion]
            if (not expansionDungeonData) then
                expansionDungeonData = {}
                _detalhes.dungeon_data [expansion] = expansionDungeonData
            end

            --store information about the dungeon run
            --the the dungeon ID, can't be localized
            --players in the group
            --difficulty level
            --

        end
        --]=]
    end
end

function DetailsMythicPlusFrame.MythicDungeonStarted()
    --flag as a mythic dungeon
    DetailsMythicPlusFrame.IsDoingMythicDungeon = true

    --this counter is individual for each character
    Details.mythic_dungeon_id = Details.mythic_dungeon_id + 1

    local mythicLevel = C_ChallengeMode.GetActiveKeystoneInfo()
    local zoneName, _, _, _, _, _, _, currentZoneID = GetInstanceInfo()

    local mapID = C_Map.GetBestMapForUnit("player")

    if (not mapID) then
        return
    end

    local ejID = DF.EncounterJournal.EJ_GetInstanceForMap(mapID)

    --setup the mythic run info
    Details.MythicPlus.Started = true
    Details.MythicPlus.DungeonName = zoneName
    Details.MythicPlus.DungeonID = currentZoneID
    Details.MythicPlus.StartedAt = time()+9.7 --there's the countdown timer of 10 seconds
    Details.MythicPlus.EndedAt = nil --reset
    Details.MythicPlus.SegmentID = 1
    Details.MythicPlus.Level = mythicLevel
    Details.MythicPlus.ejID = ejID
    Details.MythicPlus.PreviousBossKilledAt = time()

    Details:SaveState_CurrentMythicDungeonRun(Details.mythic_dungeon_id, zoneName, currentZoneID, time()+9.7, 1, mythicLevel, ejID, time())

    local name, groupType, difficultyID, difficult = GetInstanceInfo()
    if (groupType == "party" and Details.overall_clear_newchallenge) then
        Details.historico:ResetOverallData()
        Details:Msg("the overall data has been reset.") --localize-me

        if (Details.debug) then
            Details:Msg("(debug) timer is for a mythic+ dungeon, overall has been reseted.")
        end
    end

    if (DetailsMythicPlusFrame.DevelopmentDebug) then
        print("Details!", "MythicDungeonStarted() > State set to Mythic Dungeon, new combat starting in 10 seconds.")
    end
end

function DetailsMythicPlusFrame.OnChallengeModeStart()
    --is this a mythic dungeon?
    local _, _, difficultyID, _, _, _, _, currentZoneID = GetInstanceInfo()

    if (difficultyID == 8) then
        --start the dungeon on Details!
        DetailsMythicPlusFrame.MythicDungeonStarted()
        Details222.MythicPlus.LogStep("OnChallengeModeStart()")
    else
        --print("D! mythic dungeon was already started!")
        --from zone changed
        local mythicLevel = C_ChallengeMode.GetActiveKeystoneInfo()
        local zoneName, _, _, _, _, _, _, currentZoneID = GetInstanceInfo()

        --print("Details.MythicPlus.Started", Details.MythicPlus.Started)
        --print("Details.MythicPlus.DungeonID", Details.MythicPlus.DungeonID)
        --print("currentZoneID", currentZoneID)
        --print("Details.MythicPlus.Level", Details.MythicPlus.Level)
        --print("mythicLevel", mythicLevel)

        if (not Details.MythicPlus.Started and Details.MythicPlus.DungeonID == currentZoneID and Details.MythicPlus.Level == mythicLevel) then
            Details.MythicPlus.Started = true
            Details.MythicPlus.EndedAt = nil
            Details.mythic_dungeon_currentsaved.started = true
            DetailsMythicPlusFrame.IsDoingMythicDungeon = true

            --print("D! mythic dungeon was NOT already started! debug 2")
        end
    end
end

--make an event listener to sync combat data
DetailsMythicPlusFrame.EventListener = Details:CreateEventListener()
DetailsMythicPlusFrame.EventListener:RegisterEvent("COMBAT_ENCOUNTER_START")
DetailsMythicPlusFrame.EventListener:RegisterEvent("COMBAT_ENCOUNTER_END")
DetailsMythicPlusFrame.EventListener:RegisterEvent("COMBAT_PLAYER_ENTER")
DetailsMythicPlusFrame.EventListener:RegisterEvent("COMBAT_PLAYER_LEAVE")
DetailsMythicPlusFrame.EventListener:RegisterEvent("COMBAT_MYTHICDUNGEON_START")
DetailsMythicPlusFrame.EventListener:RegisterEvent("COMBAT_MYTHICDUNGEON_END")

function DetailsMythicPlusFrame.EventListener.OnDetailsEvent(contextObject, event, ...)
    --these events triggers within Details control functions, they run exactly after details! creates or close a segment
    if (event == "COMBAT_PLAYER_ENTER") then


    elseif (event == "COMBAT_PLAYER_LEAVE") then
        --ignore the event if ignoring mythic dungeon special treatment
        if (Details.streamer_config.disable_mythic_dungeon) then
            return
        end

        if (DetailsMythicPlusFrame.IsDoingMythicDungeon) then
            local combatObject = ...

            if (combatObject.is_boss) then
                if (not combatObject.is_boss.killed) then
                    local encounterName = combatObject.is_boss.encounter
                    local zoneName = combatObject.is_boss.zone
                    local mythicLevel = C_ChallengeMode.GetActiveKeystoneInfo()

                    --just in case the combat get tagged as boss fight
                    Details.tabela_vigente.is_boss = nil

                    --tag the combat as mythic dungeon trash
                    local zoneName, instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceMapID, instanceGroupSize = GetInstanceInfo()
                    Details.tabela_vigente.is_mythic_dungeon_trash = {
                        ZoneName = zoneName,
                        MapID = instanceMapID,
                        Level = Details.MythicPlus.Level,
                        EJID = Details.MythicPlus.ejID,
                    }

                    Details222.MythicPlus.LogStep("COMBAT_PLAYER_LEAVE | wiped on boss | key level: | " .. mythicLevel .. " | " .. (encounterName or "") .. " " .. zoneName)
                else
                    DetailsMythicPlusFrame.BossDefeated(false, combatObject.is_boss.id, combatObject.is_boss.name, combatObject.is_boss.diff, 5, 1)
                end
            end

        end

    elseif (event == "COMBAT_ENCOUNTER_START") then
        --ignore the event if ignoring mythic dungeon special treatment
        if (Details.streamer_config.disable_mythic_dungeon) then
            Details222.MythicPlus.LogStep("COMBAT_ENCOUNTER_START | streamer_config.disable_mythic_dungeon is true and the code cannot continue.")
            return
        end

        local encounterID, encounterName, difficultyID, raidSize, endStatus = ...
        --nothing

    elseif (event == "COMBAT_ENCOUNTER_END") then
        --ignore the event if ignoring mythic dungeon special treatment
        if (Details.streamer_config.disable_mythic_dungeon) then
            Details222.MythicPlus.LogStep("COMBAT_ENCOUNTER_END | streamer_config.disable_mythic_dungeon is true and the code cannot continue.")
            return
        end

        local encounterID, encounterName, difficultyID, raidSize, endStatus = ...
        --nothing

    elseif (event == "COMBAT_MYTHICDUNGEON_START") then
        local lowerInstance = Details:GetLowerInstanceNumber()
        if (lowerInstance) then
            lowerInstance = Details:GetInstance(lowerInstance)
            if (lowerInstance) then
                C_Timer.After(3, function()
                    --if (lowerInstance:IsEnabled()) then
                        --todo, need localization
                        --lowerInstance:InstanceAlert("Details!" .. " " .. "Damage" .. " " .. "Meter", {[[Interface\AddOns\Details\images\minimap]], 16, 16, false}, 3, {function() end}, false, true)
                    --end
                end)
            end
        end

        --ignore the event if ignoring mythic dungeon special treatment
        if (Details.streamer_config.disable_mythic_dungeon) then
            return
        end

        --reset spec cache if broadcaster requested
        if (Details.streamer_config.reset_spec_cache) then
            Details:Destroy(Details.cached_specs)
        end

        C_Timer.After(0.25, DetailsMythicPlusFrame.OnChallengeModeStart)

        --debugging
        local mPlusSettings = Details.mythic_plus
        local result = ""
        for key, value in pairs(Details.mythic_plus) do
			if (type(value) ~= "table") then
				result = result .. key .. " = " .. tostring(value) .. " | "
			end
		end

        local mythicLevel = C_ChallengeMode.GetActiveKeystoneInfo()
        local zoneName, _, _, _, _, _, _, currentZoneID = GetInstanceInfo()
		Details222.MythicPlus.LogStep("COMBAT_MYTHICDUNGEON_START | settings: " .. result .. " | level: " .. mythicLevel .. " | zone: " .. zoneName .. " | zoneId: " .. currentZoneID)

    elseif (event == "COMBAT_MYTHICDUNGEON_END") then
        --ignore the event if ignoring mythic dungeon special treatment
        if (Details.streamer_config.disable_mythic_dungeon) then
            Details222.MythicPlus.LogStep("COMBAT_MYTHICDUNGEON_END | streamer_config.disable_mythic_dungeon is true and the code cannot continue.")
            return
        end

        --delay to wait the encounter_end trigger first
        --assuming here the party cleaned the mobs kill objective before going to kill the last boss
        C_Timer.After(2, DetailsMythicPlusFrame.MythicDungeonFinished)
    end
end

DetailsMythicPlusFrame:SetScript("OnEvent", function(_, event, ...)
    if (event == "START_TIMER") then
        --DetailsMythicPlusFrame.LastTimer = GetTime()

    elseif (event == "ZONE_CHANGED_NEW_AREA") then
        if (DetailsMythicPlusFrame.IsDoingMythicDungeon) then
            if (DetailsMythicPlusFrame.DevelopmentDebug) then
                print("Details!", event, ...)
                print("Zone changed and is Doing Mythic Dungeon")
            end

            --ignore the event if ignoring mythic dungeon special treatment
            if (Details.streamer_config.disable_mythic_dungeon) then
                Details222.MythicPlus.LogStep("ZONE_CHANGED_NEW_AREA | streamer_config.disable_mythic_dungeon is true and the code cannot continue.")
                return
            end

            local _, _, difficulty, _, _, _, _, currentZoneID = GetInstanceInfo()
            if (currentZoneID ~= Details.MythicPlus.DungeonID) then
                if (DetailsMythicPlusFrame.DevelopmentDebug) then
                    print("Zone changed and the zone is different than the dungeon")
                end

                Details222.MythicPlus.LogStep("ZONE_CHANGED_NEW_AREA | player has left the dungeon and Details! finished the dungeon because of that.")

                --send mythic dungeon end event
                Details:SendEvent("COMBAT_MYTHICDUNGEON_END")

                --finish the segment
                DetailsMythicPlusFrame.BossDefeated(true)

                --finish the mythic run
                DetailsMythicPlusFrame.MythicDungeonFinished(true)
            end
        end
    end
end)
