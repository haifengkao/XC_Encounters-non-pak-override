#!/usr/bin/env ruby

require 'pathname'
APP_PATH = File.join(Pathname.new(File.expand_path File.dirname(__FILE__)).realpath.to_s, "/")
$: << APP_PATH

require 'json'
require 'fileutils'

require 'StatusData.rb'

require_relative '../LSP4Plugin'

$errors = []

def main(appPath, argv)
	puts argv
	filename = File.join(argv[0], "SkillGenerationFile.txt")
	outPath = Pathname.new(File.join(argv[0], "../")).cleanpath.to_s

	puts "Generation File: " + filename
	puts "Outdir: " + outPath
	if InitP4("Skill Generation")
		retVal = Parse(filename, outPath)
		P4RevertUnchanged()
	else
		puts "Could not make P4 connection!"
	end
	return retVal;
end

def ReadBaseFile(file)
	if !File.exists?(file)
		$errors << "Could not find script base file: " + file;		
	else
		begin
			return File.readlines(file)
		rescue		
			$errors << "Found, but could not read script base file: " + file;		
		end
	end
	
	return nil
end

class BaseScriptContainer
	
	def initialize(path)
		@baseScriptSkillIterator = ReadBaseFile(File.join(path, "Generator/_SKILL_Gen_Iterate.charScript"))
		@baseScriptSkillNoIterator = ReadBaseFile(File.join(path, "Generator/_SKILL_Gen_NoIterate.charScript"))
		@baseScriptPotion = ReadBaseFile(File.join(path, "Generator/_POTION_Gen.charScript"))
		@baseScriptSkillFromItemIterate = ReadBaseFile(File.join(path, "Generator/_SKILLFROMITEM_Gen_Iterate.charScript"))
		@baseScriptSkillFromItemNoIterate = ReadBaseFile(File.join(path, "Generator/_SKILLFROMITEM_Gen_NoIterate.charScript"))
	end 
	
	def GetBaseScript(item)
		baseScript = nil
		type = item["Base Script"]
		if type == "Potion"
			baseScript = @baseScriptPotion
		else
			target = item["Target: Alignment"] 
			iter = target == "Self" || target == "None"
			if type == "Scroll" || type == "Arrow" || type == "Grenade"
				if !iter
					baseScript = @baseScriptSkillFromItemIterate
				else
					baseScript = @baseScriptSkillFromItemNoIterate
				end				
			else
				if !iter
					baseScript = @baseScriptSkillIterator
				else
					baseScript = @baseScriptSkillNoIterator
				end
			end
		end
		return baseScript
	end
	
end

def GetActionFilePrefix(data)
	return data["Base Script"].upcase() + "_"
end

def Parse(inputFile, outputDir)
	
	baseScripts = BaseScriptContainer.new(outputDir)
	
	if !File.exists?(inputFile)
		$errors << "Could not find input file: " + inputFile;
	end
	
	if $errors.length == 0
		data = nil
		begin
			f = File.open( inputFile, "r" )
			data = JSON.load( f )
			f.close()
		rescue
			$errors << "Found, but could not open/parse input file: " + inputFile;	
		end
		
		if data != nil
			root = data["Skills"]
			for item in root
				prefix = GetActionFilePrefix(item)
				actionFile = File.join(outputDir, prefix + item["Action"] + ".charScript")
				AddSkill(actionFile, item, baseScripts.GetBaseScript(item))
			end
		end
	end
end

class EventContext
	attr_accessor :actionContext, :name, :vars, :on
	def initialize(actionContext, name)
		@actionContext = actionContext
		@name = name
		@vars = []
		@checks = []
		@on = []
	end	
end

class ActionContext
	attr_accessor :action, :char, :base, :globalVars, :events, :actions
	def initialize(action, char, base)
		@action = action
		@char = char
		@base = base
		@globalVars = []
		@events = []
		@actions = []
	end	
end

class Context
	attr_accessor :actionContext, :vars, :checks, :conditions, :actions, :preactions, :elseContext
				
	def initialize(actionContext)
		@actionContext = actionContext
		@vars = []
		@checks = []
		@conditions = []
		@actions = []
		@preactions = []
		@elseContext = nil
	end
	
	def action
		return @actionContext.action
	end
  
	def char
		return @actionContext.char
	end
	
	def base
		return @actionContext.base
	end
	
end

class SubContext
	attr_accessor :parentContext, :checks, :conditions, :actions, :elseContext
				
	def initialize(parentContext)
		@parentContext = parentContext
		@checks = []
		@conditions = []
		@actions = []
		@elseContext = nil
	end
	
	def actionContext
		return @parentContext.actionContext
	end

	def vars
		return @parentContext.vars
	end

	def action
		return @parentContext.action
	end

	def preactions
		return @parentContext.preactions
	end
  
	def char
		return @parentContext.char
	end
	
	def base
		return @parentContext.base
	end
	
end

class FileContex
	attr_accessor :file, :ifOpen
	
	def initialize(file)
		@file = file
		@ifOpen = nil
	end
	
end

module Comp
  OVERRIDE = 1
  AND = 2
  OR = 3
end

def RemoveTab(line)
	if line[0] == "\t"
		return line[1..-1]
	else
		return line[4..-1]
	end
end

def WriteList(fileContex, line, id, genId, list)
	endIndex = line.index(id)
	if endIndex != nil
		if endIndex != 0
			tab = line[0..endIndex-1]
			tab = tab == nil ? "" : tab
		else 
			tab = ""
		end
		
		fileContex.file.puts tab + "// [#{genId}]"
		for i in list
			fileContex.file.puts tab + i
		end
		fileContex.file.puts tab + "// [~#{genId}]"
		return true
	end
	return false
end

def WriteContext(fileContex, line, id, genId, context)
	startIndex = line.index(id)
	if startIndex != nil
		WriteList(fileContex, line, id, genId+"_PRE", context.preactions)
		WriteList(fileContex, line, id, genId, context.actions)
	end	
	return startIndex != nil
end

def AddFileActions(preproContext, line, startStr, endStr, context)	
	startIndex = line.index(startStr)
	if startIndex != nil
		preproContext.eat = true
		preproContext.ifOpen = startStr
	elsif preproContext.ifOpen == startStr
		preproContext.eat = true
		calcCheckEndIndex = line.index(endStr)
		if calcCheckEndIndex != nil
			preproContext.ifOpen = nil
		else	
			CreateAction(RemoveTab(line), context)
		end
	end
end

class MergeContextDesc
	attr_accessor :parentContext, :topLevelContext

	def parentContext
		return @parentContext
	end

	def topLevelContext
		return @topLevelContext
	end

end

def MergeContext(context, mergeContext, endNode)
	if context.checks.length > 0 || endNode
		if mergeContext.parentContext != nil
			mergeContext.parentContext.elseContext = context
		end
		mergeContext.parentContext = context
		if mergeContext.topLevelContext == nil
			mergeContext.topLevelContext = context
		end
	end
end

class PreproContext
	attr_accessor :eat, :ifOpen
	
	def initialize()
		@eat = false
		@ifOpen = nil
	end
end

def AddSkill(file, data, base)
	action = data["Action"]
	
	puts "Adding action: " + action + " => " + file

	f = nil

	P4CheckOut(file)
	begin
		f = File.open( file, "w" )
	rescue
		$errors << "Could not open file " + file
	end
	P4Add(file)
	
	if f != nil
		action = data["Action"]
		
		vars = []
		checks = []
		conditions = []
		
		actionContext = ActionContext.new(action, "__Me", data["Base Script"])

		needsIterate = false
		target = data["Target: Alignment"]
		if target != "Self" && target != "None"
			needsIterate = true
		end

		comp = $COMP_TABLE["Compare"]
		if comp == nil
			comp = "Vitality"
		end
		compType = $COMP_FUNC_TABLE["CompareType"]
		if compType == nil
			compType = "Random"
		end

		# Generate Contexts		
		globalContext = Context.new(actionContext)
		globalCheckContext = SubContext.new(globalContext)
		targetPosIf = SubContext.new(globalContext)
		targetSurfIf = SubContext.new(globalContext)
		targetContext = nil
		targetSubContext = nil
		elseContext = nil
		if needsIterate
			elseContext = SubContext.new(globalContext)

			targetContext = Context.new(actionContext)
			targetSubContext = SubContext.new(targetContext)
		else
			targetSubContext = SubContext.new(globalContext)
		end
			
		GenerateGlobalConditions(data, globalCheckContext)
		AddPositionCheck(data, targetPosIf)
		AddSurfaceCheck(data, targetSurfIf)
		if needsIterate
			actionContext.char = "_Char"
		end
		GenerateTargetConditions(data, targetSubContext)
		GenerateTargetsScoring(data, targetSubContext)
		# ~Generate Contexts

		# Merge Contexts
		mergeContext = MergeContextDesc.new()
		MergeContext(targetPosIf, mergeContext, false)
		MergeContext(targetSurfIf, mergeContext, false)
		if needsIterate
			MergeContext(elseContext, mergeContext, true)
		else
			MergeContext(targetSubContext, mergeContext, true)
		end
		# ~Merge Contexts

		cantSeeScore = $WEIGHT_TABLE["CantSee"].to_s

		skillOverride = data["SkillOverride"];
		if skillOverride == nil || skillOverride == ""
		   skillOverride = "null"
		end

		preprocessedFile = []

		preproContext = PreproContext.new()
		for line in base
			preproContext.eat = false

			myline = line.gsub("[ACTION]", action)
			myline.gsub!("[CANT_SEE_SCORE]", cantSeeScore)
			myline.gsub!("[COMP]", comp)
			myline.gsub!("[COMPFUNC]", compType)
			myline.gsub!("[SKILLOVERRIDE]", skillOverride)
			myline.gsub!("[CHAR_SCORE]", "_Score")
			myline.gsub!("[POS_SCORE]", "#{$WEIGHT_TABLE["PositionTargetScore"]}")
			myline.gsub!("[TARGET_POS]", "_TargetPos")

			AddFileActions(preproContext, myline, "[CALC_POS_ACTIONS]", "[CALC_POS_ACTIONS_END]", targetPosIf)
			AddFileActions(preproContext, myline, "[CALC_POS_ACTIONS]", "[CALC_POS_ACTIONS_END]", targetSurfIf)
			if needsIterate
				AddFileActions(preproContext, myline, "[CALC_CHAR_ACTIONS]", "[CALC_CHAR_ACTIONS_END]", elseContext)
				AddFileActions(preproContext, myline, "[CALC_CHAR_TARGET_ACTIONS]", "[CALC_CHAR_TARGET_ACTIONS_END]", targetSubContext)
			else
				AddFileActions(preproContext, myline, "[CALC_CHAR_ACTIONS]", "[CALC_CHAR_ACTIONS_END]", targetSubContext)
			end
			if preproContext.eat == false
				preprocessedFile.push(myline)
			end
		end

		if globalCheckContext.checks.length > 0
			CreateIfCheck(mergeContext.topLevelContext, globalCheckContext)
			mergeContext.topLevelContext = globalCheckContext
		end
		CreateIfCheck(mergeContext.topLevelContext, globalContext)

		if targetContext
			CreateIfCheck(targetSubContext, targetContext)			
		end

		globalContext.preactions.concat(actionContext.actions)

		
		fileContex = FileContex.new(f)
		
		for myline in preprocessedFile		

			eventsIndex = myline.index("[EVENTS]")
			# If global section
			if eventsIndex != nil
				tab = myline[0,eventsIndex]
				tab = tab == nil ? "" : tab
				tab2 = tab + "    "
				f.puts tab + "// [EVENTS]"
				for event in actionContext.events
					f.puts "#{tab}EVENT #{event.name}"
					f.puts "#{tab}VARS"
					for var in event.vars
						f.puts tab2 + var
					end					
					f.puts "#{tab}ON" 
					for o in event.on
						f.puts tab2 + o
					end		
					f.puts "#{tab}ACTIONS" 
					for act in event.actions
						f.puts tab2 + act
					end
					f.puts ""
				end
				f.puts tab + "// [~EVENTS]"
			elsif WriteList(fileContex, myline, "[GLOBAL_VARS]", "GLOBAL_VARS", actionContext.globalVars)
			
			elsif WriteList(fileContex, myline, "[CALC_VARS]", "CALC_VARS", globalContext.vars)
			elsif WriteContext(fileContex, myline, "[CALC_PRE_ACTIONS]", "CALC_ACTIONS", globalContext)

			elsif needsIterate && WriteList(fileContex, myline, "[CALC_TARGET_VARS]", "CALC_TARGET_VARS", targetContext.vars)
			elsif needsIterate && WriteContext(fileContex, myline, "[CALC_CHAR_TARGET_PRE_ACTIONS]", "CALC_CHAR_TARGET_ACTIONS", targetContext)

			else
				f << myline
			end
		end
		
		f.close()
	end
end

###############################################################################
###############################################################################
###############################################################################

def CreateConditionCheckString(checks)
	if checks.length > 0
		condStr = "\"("
		for check in checks
			condStr += check + ")&("
		end
			
		condStr[-2] = "\""
		return condStr[0..-2]
	end
	return ""
end

###############################################################################
###############################################################################
###############################################################################

def CreateGlobalAction(action, context)
	context.actionContext.actions.push(action.clone)
end

def CreateEventBlock(eventContext, context)
	context.actionContext.events.push(eventContext)
end

def CreateEvent(name, eventContext)
	eventContext.on.push(name)
end

def GetEvent(name, context)
	events = context.actionContext.events
	for i in events
		if i.name == name
			return i
		end
	end	
	return nil
end

def CreateAction(action, context)
	context.actions.push(action.clone)
end

def CreatePreAction(action, context)
	context.preactions.push(action.clone)
end

def CreateCheck(check, context)
	context.checks.push(check.clone)
end

def CreateCondition(cond, value, outCheck, compMode, context)
	valueStr = ""
	if !value
		valueStr = "!"
	end
	index = context.conditions.index(cond)
	if index == nil
		index = context.conditions.length
		context.conditions.push(cond + " // c#{(index+1).to_s}")
	end
	index += 1
	check = valueStr + "c" + index.to_s
	if compMode == Comp::OVERRIDE || outCheck == ""
		outCheck.replace(check)
	elsif compMode == Comp::AND
		outCheck.concat("&#{check}")
	elsif compMode == Comp::OR
		outCheck.replace("(#{outCheck})|#{check}")
	else
		raise "Unknown Comp value"
	end
end

def CreateVariable(type, var, context)
	varStr = type + ":" + var
	if context.vars.index(varStr) == nil
		context.vars.push(varStr)
		return true
	end
	return false
end

def CreateGlobalVariable(type, var, context)
	varStr = type + ":" + var
	if context.actionContext.globalVars.index(varStr) == nil
		context.actionContext.globalVars.push(varStr)
		return true
	end
	return false
end

def CreateIfCheck(subContext, context, fromIf = false)
	hasChecks = subContext.conditions.length != 0
	
	if hasChecks || fromIf
		tab = "    "
		ifStr = "IF"
		if fromIf
			if hasChecks
				ifStr = "ELIF"
			else
				ifStr = "ELSE"
			end
		end
		CreateAction("#{ifStr} " + CreateConditionCheckString(subContext.checks), context)
		for cond in subContext.conditions
			CreateAction("#{tab}#{cond}", context)
		end
		if hasChecks
			CreateAction("THEN", context)
		end
	else
		tab = ""
	end
	for action in subContext.actions
		CreateAction("#{tab}#{action}", context)		
	end
	if hasChecks || fromIf
		if subContext.elseContext != nil
			CreateIfCheck(subContext.elseContext, context, true)
		else
			CreateAction("ENDIF", context)
		end
	end
end

###############################################################################
########################      GlobalConditions      ###########################
###############################################################################

def GetWeaponRange(outMin, outMax, context)
	outMin.replace("_WeaponRangeMin")
	outMax.replace("_WeaponRangeMax")
	if CreateVariable("FLOAT", outMin, context) && CreateVariable("FLOAT", outMax, context)
		check = ""
		CreateCondition("CharacterGetWeaponRange(#{outMin}, #{outMax}, __Me)", true, check, Comp::OVERRIDE, context)
		CreateCheck(check, context)
	end	
end

def GetSkillRange(outMin, outMax, context)
	outMin.replace("_SkillRangeMin")
	outMax.replace("_SkillRangeMax")
	if CreateVariable("FLOAT", outMin, context) && CreateVariable("FLOAT", outMax, context)
		skill = context.action
		if context.base == "Arrow" || context.base == "Scroll" || context.base == "Grenade"
			skill = "%SkillID_#{context.action}"
		end
		check = ""
		CreateCondition("CharacterGetSkillRange(#{outMin}, #{outMax}, __Me, #{skill})", true, check, Comp::OVERRIDE, context)
		CreateCheck(check, context)
	end	
end

def GetSkillImpactRange(outRange, context)
	outRange.replace("_SkillImpactRange")
	if CreateVariable("FLOAT", outRange, context)
		skill = context.action
		if context.base == "Arrow" || context.base == "Scroll" || context.base == "Grenade"
			skill = "%SkillID_#{context.action}"
		end
		check = ""
		CreateCondition("CharacterGetSkillImpactRange(#{outRange}, __Me, #{skill})", true, check, Comp::OVERRIDE, context)
		CreateCheck(check, context)
	end	
end

def GenerateGlobalConditions(data, context)
	AddGlobalStatusChecks(data, context)
end

def AddGlobalStatusChecks(data, context)
	statuses = data["Self: Status"]
	notStatuses = data["Self: Not Status"]
	
	check = GetStatusChecks(statuses, true, context)
	if check != ""
		CreateCheck(check, context)
	end
	check = GetStatusChecks(notStatuses, true, context)
	if check != ""
		check = "!(#{check})"
		CreateCheck(check, context)
	end
end

def AddCharacterCount(context, varName, range, relation, surface)
	#OUT INT:count, GAMEOBJECT|FLOAT3:src, FLOAT:range, [RELATION: relation, SURFACE:surface, STATUS:status, TALENT:talent, CHARACTER:inSightOf]
	if CreateVariable("INT", varName, context)
		check = ""
		CreateCondition("CharacterCount(#{varName}, #{context.char}, #{range}, #{relation}, #{surface})", true, check, Comp::OVERRIDE, context)
		CreateCheck(check, context)
	end	
end

def AddDistanceConditions(context, type, outDist, outMin, outMax)
	check = ""
	if type == "TargetInRange"
		
		outDist.replace("_DistanceToChar")
		GetSkillRange(outMin, outMax, context)
		
		if CreateVariable("FLOAT", outDist, context)					
			CreateCondition("GetDistance(#{outDist}, __Me, #{context.char})", true, check, Comp::AND, context)
		end
		
	elsif type == "TargetInWeaponRange"
	
		outDist.replace("_DistanceToChar")
		GetWeaponRange(outMin, outMax, context)

		if CreateVariable("FLOAT", outDist, context)
			CreateCondition("GetDistance(#{outDist}, __Me, #{context.char})", true, check, Comp::AND, context)
		end
				
	else
		$errors << "Unknown Distance Condition type (#{type}) for action #{context.action} found"	
	end
	
	if check.length > 0
		CreateCheck(check, context)
	end
end

###############################################################################
###########################     Position Check     ############################
###############################################################################

def AddPositionCheck(data, context)
	posCheck = data["Pos: Conditions"]
	if posCheck != nil && posCheck != "-"

		outVar = "_TargetPos"
		minRange = ""
		maxRange = ""
		aoeRange = ""
		alignSource = "__Me"
		minAllies = -1
		maxAllies = -1
		minEnemies = -1
		maxEnemies = -1

		if posCheck == "SeveralFriendsInAOE"
			GetSkillRange( minRange, maxRange, context )
			GetSkillImpactRange( aoeRange, context )
			minAllies = $TARGET_POSITION_TABLE["SeveralFriends"]
		elsif posCheck == "SeveralEnemiesInAOE"
			GetSkillRange( minRange, maxRange, context )
			GetSkillImpactRange( aoeRange, context )
			minEnemies = $TARGET_POSITION_TABLE["SeveralEnemies"]
		elsif posCheck == "SeveralFriendsInAOENoEnemies"
			GetSkillRange( minRange, maxRange, context )
			GetSkillImpactRange( aoeRange, context )
			minAllies = $TARGET_POSITION_TABLE["SeveralFriends"]
			maxEnemies = 0
		elsif posCheck == "SeveralEnemiesInAOENoFriends"
			GetSkillRange( minRange, maxRange, context )
			GetSkillImpactRange( aoeRange, context )
			minEnemies = $TARGET_POSITION_TABLE["SeveralEnemies"]
			maxAllies = 0
			
		elsif posCheck == "SeveralFriendsInRange"
			GetSkillRange( minRange, maxRange, context )
			aoeRange = $TARGET_POSITION_TABLE["InRangeRange"]
			minAllies = $TARGET_POSITION_TABLE["SeveralFriends"]
		elsif posCheck == "SeveralEnemiesInRange"
			GetSkillRange( minRange, maxRange, context )
			aoeRange = $TARGET_POSITION_TABLE["InRangeRange"]
			minEnemies = $TARGET_POSITION_TABLE["SeveralEnemies"]
		elsif posCheck == "SeveralFriendsInRangeNoEnemies"
			GetSkillRange( minRange, maxRange, context )
			aoeRange = $TARGET_POSITION_TABLE["InRangeRange"]
			minAllies = $TARGET_POSITION_TABLE["SeveralFriends"]
			maxEnemies = 0
		elsif posCheck == "SeveralEnemiesInRangeNoFriends"
			GetSkillRange( minRange, maxRange, context )
			aoeRange = $TARGET_POSITION_TABLE["InRangeRange"]
			minEnemies = $TARGET_POSITION_TABLE["SeveralEnemies"]
			maxAllies = 0
			
		elsif posCheck == "SafePosition"
			GetSkillRange( minRange, maxRange, context )
			maxEnemies = 0
			aoeRange = $TARGET_POSITION_TABLE["SaveRange"]
		else
			$errors << "Unknown Pos Condition #{posCheck} in action #{context.action}"
			return
		end

		CreateVariable("FLOAT3", "#{outVar}", context)
		check = ""
		CreateCondition("FindPosition(#{outVar}, #{context.char}, #{maxRange}, #{aoeRange}, #{alignSource}, #{minAllies}, #{maxAllies}, #{minEnemies}, #{maxEnemies})", true, check, Comp::OVERRIDE, context)
		CreateCheck(check, context)
	end
end

###############################################################################
###########################     Surface Check      ############################
###############################################################################

def AddSurfaceCheck(data, context)
	surfTypesStr = data["Surface: Type"]
	if surfTypesStr != nil && surfTypesStr != ""
		check = ""
		surfTypes = surfTypesStr.split("|")
		for surfType in surfTypes
			outVar = "_TargetPos"
			minRange = ""
			maxRange = ""
			surface = surfType
			#aoeRange = ""
			alignSource = "__Me"
			minCellCount = 10
			minEnemies = data["Surface: Min Enemies"]
			maxAllies = data["Surface: Max Allies"]

			GetSkillRange( minRange, maxRange, context )
			#GetSkillImpactRange( aoeRange, context )

			CreateVariable("FLOAT3", "#{outVar}", context)
			CreateCondition("FindSurface(#{outVar}, #{context.char}, #{minRange}, #{maxRange}, #{surface}, #{alignSource}, #{minEnemies}, #{maxAllies}, #{minCellCount})", true, check, Comp::OR, context)
		end
		CreateCheck(check, context)
	end
end


###############################################################################
##############################     Scoring     ################################
###############################################################################

def GenerateTargetsScoring(data, context)
	if CreateVariable("FLOAT", "_Score", context)
		CreatePreAction("Set(_Score, 0.0)", context)
	end
	AddPreferedStatusScores(data, context, true)
	AddPreferedStatusScores(data, context, false)
	AddFrequencyScore(data, context)
	AddDistanceScore(data, context)
end

def AddPreferedStatusScores(data, context, isPreferred)
	if isPreferred
		statusString = data["Target: PrefStatus"]
	else
		statusString = data["Target: PrefNotStatus"]
	end
	statusesLength = statusString.length
	scopeDepth = 0
	startIndex = 0
	for i in 0..statusesLength
		c = statusString[i]
		if (c != " ")		
			if c == "("
				scopeDepth += 1
			end
			if c == ")"
				scopeDepth -= 1
			end
			if c == "|"
				if scopeDepth == 0
					AddPreferedStatusScore(statusString[startIndex..i-1], context, isPreferred)
					startIndex = i + 1
				end
			end	
		end
	end
	if startIndex < statusesLength - 1
		AddPreferedStatusScore(statusString[startIndex..i-1], context, isPreferred)
		startIndex = i + 1
	end
end

def AddPreferedStatusScore(str, context, isPreferred)
	subContext = SubContext.new(context)
	check = GetStatusChecks(str, true, subContext)
	CreateCheck(check, subContext)
	if isPreferred
		CreateAction("Add(_Score, #{$WEIGHT_TABLE["PrefStatusScore"]})", subContext)
	else
		CreateAction("Add(_Score, #{$WEIGHT_TABLE["PrefNotStatusScore"]})", subContext)
	end
	CreateIfCheck(subContext, context)
end

def AddRangeCheckScore(distance, minRange, maxRange, context)
	
	CreateVariable("FLOAT", "_DistanceScore", context)
			
	CreateAction("// Range score calculation", context)
	CreateAction("Set(_DistanceScore, #{distance})", context)
	
	subContext = SubContext.new(context)
	elifContext = SubContext.new(context)
	subContext.elseContext = elifContext
	elseContext = SubContext.new(context)
	elifContext.elseContext = elseContext
	
	# IF to far
	subCheck = ""
	CreateCondition("IsGreaterThen(_DistanceScore, #{maxRange})", true, subCheck, Comp::OVERRIDE, subContext)
	CreateAction("Subtract(_DistanceScore, #{maxRange})", subContext)
	CreateAction("Multiply(_DistanceScore, #{$WEIGHT_TABLE["DistanceToFar"]})", subContext)
	CreateCheck(subCheck, subContext)
	
	# ELIF to close
	subElseIfCheck = ""
	CreateCondition("IsLessThen(_DistanceScore, #{minRange})", true, subElseIfCheck, Comp::OVERRIDE, elifContext)
	CreateAction("Subtract(_DistanceScore, #{minRange})", elifContext)
	CreateAction("Multiply(_DistanceScore, #{$WEIGHT_TABLE["DistanceToClose"]})", elifContext)
	CreateCheck(subElseIfCheck, elifContext)
	
	# ELSE
	CreateAction("Set(_DistanceScore, #{$WEIGHT_TABLE["DistanceInRange"]})", elseContext)
	
	CreateIfCheck(subContext, context)
	
	CreateAction("Add(_Score, _DistanceScore)", context)
	CreateAction("", context)
	
end

def AddCountScore(id, count, check, checkBool, val, context)
	
	CreateAction("// #{id} score calculation", context)
	
	subContext = SubContext.new(context)
	
	# IF to far
	subCheck = ""
	CreateCondition("#{check}(#{count}, #{val})", checkBool, subCheck, Comp::OVERRIDE, subContext)
	CreateAction("Add(_Score, #{$WEIGHT_TABLE["PrefStatusScore"]})", subContext)
	CreateCheck(subCheck, subContext)
	
	CreateIfCheck(subContext, context)
	
	CreateAction("", context)
	
end

def AddDistanceScore(data, context)
	
	targetRange = data["Target: Prefer"]
	check = ""
	if targetRange == "TargetInRange" || targetRange == "TargetInWeaponRange"
		dist = ""
		min = ""
		max = ""
		AddDistanceConditions(context, targetRange, dist, min, max) 
		AddRangeCheckScore(dist, min, max, context)	
	elsif targetRange == "SeveralFriendsInRange"
		AddCharacterCount(context, "_FriendsInRange", $TARGET_POSITION_TABLE["InRangeRange"], "Ally", "null")
		AddCountScore(targetRange, "_FriendsInRange", "IsLessThen", false, $TARGET_POSITION_TABLE["SeveralFriends"], context)
		
	elsif targetRange == "SeveralEnemiesInRange"
		AddCharacterCount(context, "_EnemiesInRange", $TARGET_POSITION_TABLE["InRangeRange"], "Enemy", "null")
		AddCountScore(targetRange, "_EnemiesInRange", "IsLessThen", false, $TARGET_POSITION_TABLE["SeveralEnemies"], context)
				
	elsif targetRange == "SeveralFriendsInAOE"
		aoeRange = ""
		GetSkillImpactRange( aoeRange, context )
		AddCharacterCount(context, "_FriendsInAOE", aoeRange, "Ally", "null")
		AddCountScore(targetRange, "_FriendsInAOE", "IsLessThen", false, $TARGET_POSITION_TABLE["SeveralFriends"], context)
		
	elsif targetRange == "SeveralEnemiesInAOE"
		aoeRange = ""
		GetSkillImpactRange( aoeRange, context )
		AddCharacterCount(context, "_EnemiesInAOE", aoeRange, "Enemy", "null")
		AddCountScore(targetRange, "_EnemiesInAOE", "IsLessThen", false, $TARGET_POSITION_TABLE["SeveralEnemies"], context)
		
	elsif targetRange == "NoFriendsNearTarget"
		AddCharacterCount(context, "_FriendsInRange", $TARGET_POSITION_TABLE["InRangeRange"], "Ally", "null")
		AddCountScore(targetRange, "_FriendsInRange", "IsEqual", true, 0, context)
		
	elsif targetRange == "NoEnemiesNearTarget"
		AddCharacterCount(context, "_EnemiesInRange", $TARGET_POSITION_TABLE["InRangeRange"], "Enemy", "null")
		AddCountScore(targetRange, "_EnemiesInRange", "IsEqual", true, 0, context)
		
	elsif targetRange == "-"
		# No check needed
	else
		$errors << "Unknown Target Condition type (#{targetRange}) for action #{context.action} found"
	end
	
	if check.length > 0
		CreateCheck(check, context)
	end
end

def AddFrequencyScore(data, context)
	freq = data["Hostile Count"]
	if freq != ""
		freqValue = $HOSTILE_COUNT_TABLE[freq]
		if freqValue != nil	
		
			CreateAction("// Hostile count score calculation", context)
			subContext = SubContext.new(context)
			check = ""
			if freqValue[0] != -1
				CreateCondition("IsGreaterThen(_HostileCount, #{freqValue[0]-1})", true, check, Comp::OVERRIDE, subContext)
			end
			if freqValue[1] != -1
				CreateCondition("IsLessThen(_HostileCount, #{freqValue[1]+1})", true, check, Comp::AND, subContext)
			end
			
			if check == ""
				CreateAction("Add(_Score, #{$WEIGHT_TABLE["HostileCount"]}) // HostileWeight", context)			
			else
				CreateCheck(check, subContext)
				
				if CreateVariable("INT", "_HostileCount", context)
					CreateCondition("CharacterGetHostileCount(_HostileCount, #{context.char})", true, check, Comp::OVERRIDE, context)
					CreateCheck(check, context)
				end
				CreateVariable("FLOAT", "_HostileScore=0", context)
				CreateAction("Set(_HostileScore, #{$WEIGHT_TABLE["HostileCount"]})", subContext)
				CreateIfCheck(subContext, context)
				CreateAction("Add(_Score, _HostileScore)", context)	
			end
			CreateAction("", context)
			
		else
			$errors << "Unknown Attack Frequency #{freq} found in action #{context.action}" 
		end
	end
end

###############################################################################
##########################       Conditions      ##############################
###############################################################################

def GenerateTargetConditions(data, context)
	AddAlwaysCheckChecks(data, context)
	AddClassScoreChecks(data, context)
	AddTargetStatusChecks(data, context)
	AddTargetCheck(data, context)
end

def AddAlwaysCheckChecks(data, context)
	check = ""
	
	if context.char != "__Me"
		statuses = data["Target: Condition"]
		notStatuses = data["Target: Not Condition"]
		if statuses.index("Dead") == nil && notStatuses.index("Dead") == nil
			CreateCondition("CharacterIsDead(#{context.char})", false, check, Comp::OVERRIDE, context)
		end
		CreateCondition("CharacterHasStatus(#{context.char}, INVISIBLE)", false, check, Comp::AND, context)
		CreateCondition("CharacterHasStatus(#{context.char}, SNEAKING)", false, check, Comp::AND, context)
	end
	if check != ""
		CreateCheck(check, context)
	end
end

def AddClassScoreChecks(data, context)	
	
	if context.char != "__Me" #no need to check this on me ...
		warriorScore = data["Warrior"] == nil ? 0 : data["Warrior"].to_i
		rogueScore = data["Rogue"] == nil ? 0 : data["Rogue"].to_i
		mageScore = data["Mage"] == nil ? 0 : data["Mage"].to_i
		clericScore = data["Cleric"] == nil ? 0 : data["Cleric"].to_i
		rangerScore = data["Ranger"] == nil ? 0 : data["Ranger"].to_i
		
		if warriorScore + rogueScore + mageScore + clericScore + rangerScore > 0		
			check = ""			
			prefStatus = data["Target: PrefStatus"]
			if prefStatus != ""
				check = GetStatusChecks(prefStatus, true, context)		
			end
			if CreateGlobalVariable("INT", "%ClassScore_#{context.action}", context)
				CreateGlobalAction("Set(%ClassScore_#{context.action}, 0)", context)
				CreatePreAction("Set(_ClassScore_#{context.action}, %ClassScore_#{context.action})", context)
			end
			CreateVariable("INT", "_ClassScore_#{context.action}", context)
			CreateCondition("CharacterIsBetterOrEqualClass(#{context.char}, %ClassScore_#{context.action}, _ClassScore_#{context.action}, #{warriorScore}, #{rogueScore}, #{mageScore}, #{clericScore}, #{rangerScore})", true, check, Comp::OR, context)
			CreateCheck(check, context)
			CreateAction("Set(%ClassScore_#{context.action}, _ClassScore_#{context.action})", context)
		end
	end
	
end

def AddTargetStatusChecks(data, context)
	statuses = data["Target: Condition"]
	notStatuses = data["Target: Not Condition"]
	
	check = GetStatusChecks(statuses, true, context)
	if check != ""
		CreateCheck(check, context)
	end
	check = GetStatusChecks(notStatuses, true, context)
	if check != ""
		check = "!(#{check})"
		CreateCheck(check, context)
	end
	
end

def GetStatusChecks(statusString, test, context)

	check = ""
	
	startIndex = 0
	statusesLength = statusString.length
	for i in 0..statusesLength
		c = statusString[i]
		if (c != " ")		
			if c == "(" || c == ")" || c == "|" || c == "&"
				if i > startIndex
					sub = statusString[startIndex..i-1]
					subCheck = ""
					GetStatusCheck(sub, test, subCheck, context)	
					if subCheck.length > 0
						check << "(" << subCheck << ")"
						if c == "|"
							check.replace("(#{check})")
						end
						check << c
					elsif c == ")"
						check << c
					end
				else
					check << c
				end
				
				startIndex = i + 1
			end
		end
	end
	
	if startIndex < statusesLength - 1
		sub = statusString[startIndex..statusesLength-1]
		subCheck = ""
		GetStatusCheck(sub, test, subCheck, context)
		check << "(" << subCheck << ")"
	end
		
	return check;

end

def GetStatusCheck(status, value, outCheck, context)
	if (!AddDeadCondition(status, value, outCheck, context) &&
		!AddStatusCondition(status, value, outCheck, context) &&
		!AddStatCondition(status, value, outCheck, context) &&
		!AddAbilityCondition(status, value, outCheck, context) &&
		!AddEventCondition(status, value, outCheck, context) &&
		!AddSurfaceCondition(status, value, outCheck, context) &&
		!AddDistanceCondition(status, value, outCheck, context))
		$errors << "Could not process status check #{status} for action #{context.action}"
		CreateCondition("IsEqual(INT:0, INT:0) // Placeholder because '#{status}' is unknown", value, outCheck, Comp::OVERRIDE, context)
		return false
	end
	return true
end

def AddDeadCondition(status, value, outCheck, context)
	if status == "Dead"
		CreateCondition("CharacterIsDead(#{context.char})", value, outCheck, Comp::OVERRIDE, context)
		return true
	else
		return false
	end
end

def AddStatusCondition(status, value, outCheck, context)
	val = $STATUS_TABLE[status]
	if val != nil
		extraVal = $STATUS_EXTRA_TABLE[status]
		if extraVal == nil
			CreateCondition("CharacterHasStatus(#{context.char}, #{val})", value, outCheck, Comp::OVERRIDE, context)
		else
			extraChecks = extraVal.split("|")
			outCheck.replace("")
			for extraCheck in extraChecks
				CreateCondition("CharacterHasStatus(#{context.char}, #{val}, #{extraCheck})", value, outCheck, Comp::OR, context)				
			end
		end
		return true
	else
		return false
	end
end

def AddStatCondition(status, value, outCheck, context)
	statData = $STAT_TABLE[status]
	if statData != nil
		CreateVariable("FLOAT", "_Stat#{statData[0]}", context)
		CreateCondition("CharacterGetStat(_Stat#{statData[0]}, #{context.char}, #{statData[0]})", true, outCheck, Comp::OVERRIDE, context)
		CreateCondition("#{statData[1]}(_Stat#{statData[0]}, #{statData[2].to_s})", value, outCheck, Comp::AND, context)
		return true
	else
		return false
	end
end

def AddAbilityCondition(status, value, outCheck, context)
	abData = $ABILITY_TABLE[status]
	if abData != nil
		CreateVariable("INT", "_Ability#{abData[0]}", context)
		CreateCondition("CharacterGetAbility(_Ability#{abData[0]}, #{context.char}, #{abData[0]})", true, outCheck, Comp::OVERRIDE, context)
		CreateCondition("#{abData[1]}(_Ability#{abData[0]}, #{abData[2].to_s})", value, outCheck, Comp::AND, context)
		return true
	else
		return false
	end
end

def AddEventCondition(event, value, outCheck, context)
	eventCond = $EVENT_TABLE[event]
	if eventCond != nil
		CreateCondition(eventCond.gsub("[CONTEXT]", context.char), value, outCheck, Comp::OVERRIDE, context)
		return true
	end
	return false
end

def AddSurfaceCondition(status, value, outCheck, context)
	surface = $SURFACE_TABLE[status]
	if surface != nil
		CreateCondition("IsInSurface(#{context.char}, #{surface})", value, outCheck, Comp::OVERRIDE, context)
		return true
	end
	return false
end

def AddDistanceCondition(status, value, outCheck, context)
	check = ""
	
	if status == "TargetInRange" || status == "TargetInWeaponRange"
		dist = ""
		minRange = ""
		maxRange = ""
		AddDistanceConditions(context, status, dist, minRange, maxRange)
		CreateCondition("IsLessThen(_DistanceScore, #{maxRange})", true, check, Comp::OVERRIDE, context)
		CreateCondition("IsGreaterThen(_DistanceScore, #{minRange})", true, check, Comp::AND, context)
						
	elsif status == "SeveralFriendsInRange"
		AddCharacterCount(context, "_FriendsInRange", $TARGET_POSITION_TABLE["InRangeRange"], "Ally", "null")
		CreateCondition("IsGreaterThen(_FriendsInRange, #{TARGET_POSITION_TABLE["SeveralFriends"]})", true, check, Comp::OVERRIDE, context)
		
	elsif status == "SeveralEnemiesInRange"
		AddCharacterCount(context, "_EnemiesInRange", $TARGET_POSITION_TABLE["InRangeRange"], "Enemy", "null")
		CreateCondition("IsGreaterThen(_EnemiesInRange, #{TARGET_POSITION_TABLE["SeveralEnemies"]})", true, check, Comp::OVERRIDE, context)
		
	elsif status == "SeveralFriendsInAOE"
		aoeRange = nil
		GetSkillImpactRange( aoeRange, context )
		AddCharacterCount(context, "_FriendsInAOE", aoeRange, "Ally", "null")
		CreateCondition("IsGreaterThen(_FriendsInAOE, #{TARGET_POSITION_TABLE["SeveralFriends"]})", true, check, Comp::OVERRIDE, context)
		
	elsif status == "SeveralEnemiesInAOE"
		aoeRange = nil
		GetSkillImpactRange( aoeRange, context )
		AddCharacterCount(context, "_EnemiesInAOE", aoeRange, "Enemy", "null")
		CreateCondition("IsGreaterThen(_EnemiesInAOE, #{TARGET_POSITION_TABLE["SeveralEnemies"]})", true, check, Comp::OVERRIDE, context)
		
	elsif status == "NoFriendsNearTarget"
		AddCharacterCount(context, "_FriendsInRange", $TARGET_POSITION_TABLE["InRangeRange"], "Ally", "null")
		CreateCondition("IsEqual(_FriendsInRange, 0)", true, check, Comp::OVERRIDE, context)
				
	elsif status == "NoEnemiesNearTarget"
		AddCharacterCount(context, "_EnemiesInRange", $TARGET_POSITION_TABLE["InRangeRange"], "Enemy", "null")
		CreateCondition("IsEqual(_EnemiesInRange, 0)", true, check, Comp::OVERRIDE, context)
	end
	
	if check.length > 0
		CreateCheck(check, context)
		return true
	end
	return false
end

def AddTargetCheck(data, context)
	target = data["Target: Alignment"]
	check = ""
	if target == "Enemy"
		CreateCondition("CharacterIsEnemy(__Me, #{context.char})", true, check, Comp::OVERRIDE, context)
	elsif target == "Friend"
		CreateCondition("IsEqual(__Me, #{context.char})", false, check, Comp::OVERRIDE, context)
		CreateCondition("CharacterIsAlly(__Me, #{context.char})", true, check, Comp::AND, context)
	elsif target == "Self"
		# Should not be in iterate!
	elsif target == "None"
		# Should not be in iterate!
	elsif target == "FriendOrSelf"
		CreateCondition("CharacterIsAlly(__Me, #{context.char})", true, check, Comp::OVERRIDE, context)
	elsif target == "FriendNotSummon"
		CreateCondition("CharacterIsAlly(__Me, #{context.char})", true, check, Comp::OVERRIDE, context)
		CreateCondition("CharacterIsSummon(#{context.char})", false, check, Comp::AND, context)
	elsif target == "All"
		# No check needed
	elsif target == "FriendlySummon"
		CreateCondition("CharacterIsSummon(#{context.char})", true, check, Comp::OVERRIDE, context)	
		CreateCondition("CharacterIsAlly(__Me, #{context.char})", true, check, Comp::AND, context)	
	elsif target == "EnemySummon"
		CreateCondition("CharacterIsSummon(#{context.char})", true, check, Comp::OVERRIDE, context)
		CreateCondition("CharacterIsEnemy(__Me, #{context.char})", true, check, Comp::AND, context)
	else
		$errors << "Unknown target type (#{target}) for action #{context.action} found"
	end
	
	if check.length > 0
		CreateCheck(check, context)
	end
end


###############################################################################
###############################################################################
###############################################################################

puts "Parsing : #{APP_PATH} #{ARGV}"
main(APP_PATH, ARGV)
appRetVal = 0
if ($errors.length > 0)
	
	puts ""
	puts "Error's Detected! : "
	
	for error in $errors
		puts " - " + error
	end
	
	errorPath = File.join(APP_PATH, "errors.txt")
	begin
		f = File.open(errorPath, "w")
		f.puts "Error's Detected! : "	
		for error in $errors
			f.puts " - " + error
		end
	rescue
		puts "Could not write to #{errorPath}"
	ensure
		f.close()
	end
	
	appRetVal = 1
	
end
exit(appRetVal)