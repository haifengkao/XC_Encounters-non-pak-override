
# "NameInExcel" => "StatusName"
$STATUS_TABLE =
{
	"AirShield" => "SHIELD",
	"BlackRock" => "BLACKROCKED",
	"Bleeding" => "BLEEDING",
	"Blessed" => "BLESSED",
	"Blinded" => "BLIND",
	"Burning" => "BURNING",
	"Charmed" => "CHARMED",
	"Chilled" => "CHILLED",
	"CrawlingInf" => "CRAWLING_INFESTATION",
	"Crippled" => "CRIPPLED",
	"Cursed" => "CURSED",
	"Diseased" => "DISEASED",
	"EarthShield" => "SHIELD",
	"Encumbered" => "ENCUMBERED",
	"Enraged" => "RAGED",
	"Fear" => "FEAR",
	"FireShield" => "SHIELD",
	"Fortified" => "FORTIFIED",
	"Frozen" => "FROZEN",
	"Hastened" => "HASTED",
	"Healing" => "HEALING",
	"Infected" => "INFECTIOUS_DISEASED",
	"Invisible" => "INVISIBLE",
	"Invulnerable" => "INVULNERABLE",
	"KnockedDown" => "KNOCKED_DOWN",
	"Muted" => "MUTED",
	"Petrified" => "PETRIFIED",
	"Poisoned" => "POISONED",
	"Shielded" => "SHIELD",
	"Slowed" => "SLOWED",
	"Smelly" => "SMELLY",
	"Sneaking" => "SNEAKING",
	"Stunned" => "STUNNED",
	"VoidAura" => "VOID_AURA",
	"Warm" => "WARM",
	"WaterShield" => "SHIELD",
	"Weak" => "WEAK",
	"Wet" => "WET",
	"DamageBoost" => "CONSUME",
	"PerceptionBoost" => "CONSUME",
	"AggroMark" => "AGGRO_MARKED"
}

$STATUS_EXTRA_TABLE =
{
	"FireShield" => "Shield_EnemyFire|Shield_Fire",
	"WaterShield" => "Shield_EnemyWater|Shield_Water",
	"AirShield" => "Shield_EnemyAir|Shield_Air",
	"EarthShield" => "Shield_EnemyEarth|Shield_Earth",
	"DamageBoost" => "SKILLBOOST_TargetedDamageBoost",
	"PerceptionBoost" => "SKILLBOOST_TargetedPerception"
}

# "NameInExcel" => ["StatName", "Condition", "CheckValue"]
$STAT_TABLE =
{
	"Healthy" => ["Vitality", "IsGreaterThen", 0.8],
	"Wounded" => ["Vitality", "IsLessThen", 0.6],
	"Dying" => ["Vitality", "IsLessThen", 0.3],
		
	"HighResistanceAir" => ["AirResistance", "IsGreaterThen", 50],
	"HighResistanceEarth" => ["EarthResistance", "IsGreaterThen", 50],
	"HighResistancePoison" => ["PoisonResistance", "IsGreaterThen", 50],
	"HighResistanceFire" => ["FireResistance", "IsGreaterThen", 50],
	"HighResistanceWater" => ["WaterResistance", "IsGreaterThen", 50],
	
	"LowResistanceAir" => ["AirResistance", "IsLessThen", 30],
	"LowResistanceEarth" => ["EarthResistance", "IsLessThen", 30],
	"LowResistancePoison" => ["PoisonResistance", "IsLessThen", 30],
	"LowResistanceFire" => ["FireResistance", "IsLessThen", 30],
	"LowResistanceWater" => ["WaterResistance", "IsLessThen", 30],
	
	"ImmuneToElectrifying" => ["AirResistance", "IsGreaterThen", 99],
	"ImmuneToPoisoning" => ["PoisonResistance", "IsGreaterThen", 99],
	"ImmuneToBurning" => ["FireResistance", "IsGreaterThen", 99],
	"ImmuneToFreezing" => ["WaterResistance", "IsGreaterThen", 99],
	
	"AirHeals" => ["AirResistance", "IsGreaterThen", 100],
	"EarthHeals" => ["EarthResistance", "IsGreaterThen", 100],
	"PoisonHeals" => ["PoisonResistance", "IsGreaterThen", 100],
	"FireHeals" => ["FireResistance", "IsGreaterThen", 100],
	"WaterHeals" => ["WaterResistance", "IsGreaterThen", 100]
}

# "NameInExcel" => ["AbilityName", "Condition", "CheckValue"]
$ABILITY_TABLE =
{
	"HighWillpower" => ["Willpower", "IsGreaterThen", 3],
	"LowWillpower" => ["Willpower", "IsLessThen", 2]
}

$SURFACE_TABLE =
{ 
	"InSurfaceNone" => "None",
	"InSurfaceWater" => "Water",
	"InSurfaceIce" => "Ice",
	"InSurfaceOoze" => "Ooze",
	"InSurfaceFire" => "Fire",
	"InSurfaceElectrified" => "Electrified",
	"InSurfaceOil" => "Oil",
	"InSurfaceLava" => "Lava",
	"InSurfaceBlood" => "Blood",
	"InSurfaceBloodFrozen" => "BloodFrozen",
	"InSurfaceBloodElectrified" => "BloodElectrified",
	"InSurfaceCloudPoison" => "CloudPoison",
	"InSurfaceCloudStatic" => "CloudStatic",
	"InSurfaceCloudSteam" => "CloudSteam",
	"InSurfaceCloudSmoke" => "CloudSmoke"
}

$EVENT_TABLE =
{ 
	"BeenHitByFireSpell" => "CharacterHasBeenHitBy([CONTEXT], Fire)",
	"BeenHitByWaterSpell" => "CharacterHasBeenHitBy([CONTEXT], Water)",
	"BeenHitByAirSpell" => "CharacterHasBeenHitBy([CONTEXT], Air)",
	"BeenHitByEarthSpell" => "CharacterHasBeenHitBy([CONTEXT], Earth)",
	"HasJustCastASpell" => "CharacterHasCastedSpellLastTurn([CONTEXT])",
	"BeenStunned" => "CharacterHasHadStatus([CONTEXT], STUNNED)",
	"BeenPoisoned" => "CharacterHasHadStatus([CONTEXT], POISONED)",
	"BeenBurnt" => "CharacterHasHadStatus([CONTEXT], BURNING)",
	"BeenFrozen" => "CharacterHasHadStatus([CONTEXT], FROZEN)"
}

# Target Position
$TARGET_POSITION_TABLE = 
{
	"SeveralEnemies" => 2,
	"SeveralFriends" => 2,
	"InRangeRange" => 5,
	"SaveRange" => 5.0
}

# "NameInExcel" => [lowerBound, upperBound]
# HostileCount between [A, B] 
# A = lower inclusive bound
# B = upper inclusive bound
# -1 => don't check bound
$HOSTILE_COUNT_TABLE =
{
	"Low" => [-1, 2],
	"Medium" => [1, 3],
	"High" => [3, -1],
	"Any" => [-1, -1]
}

$WEIGHT_TABLE =
{
	"DistanceToFar" => -1.0, # Multiplier on distance larger than skill max range: if distanceFromTarget < maxRange then score = (distanceFromTarget - maxRange) * DistanceToFar
	"DistanceToClose" => 1.0, # Multiplier on distance smaller than skill min range: if distanceFromTarget < minRange then score = (distanceFromTarget - minRange) * DistanceToClose
	"DistanceInRange" => 0.0, # Value when you are in range
	"HostileCount" => 10.0, # Value when AttackFrequency check succeeds
	"CantSee" => -10.0, # Value when you can't see the target
	"PrefStatusScore" => 5.0, # Added when you have one preferred status
	"PrefNotStatusScore" => -5.0, # Added when you have one not preferred status

	"PositionTargetScore" => 20.0 # Added when you target a valid position / surface
}


$COMP_TABLE =
{
	"APMaximum" => "APMaximum",
	"APRecovery" => "APRecovery",
	"APStart" => "APStart",
	"AirResistance" => "AirResistance",
	"Armor" => "Armor",
	"Constitution" => "Constitution",
	"CrushingResistance" => "CrushingResistance",
	"Dexterity" => "Dexterity",
	"Distance" => "Distance",
	"EarthResistance" => "EarthResistance",
	"FireResistance" => "FireResistance",
	"Hearing" => "Hearing",
	"Initiative" => "Initiative",
	"Intelligence" => "Intelligence",
	"Perception" => "Perception",
	"PiercingResistance" => "PiercingResistance",
	"PoisonResistance" => "PoisonResistance",
	"Reputation" => "Reputation",
	"ShadowResistance" => "ShadowResistance",
	"Sight" => "Sight",
	"SlashingResistance" => "SlashingResistance",
	"Speed" => "Speed",
	"Strength" => "Strength",
	"Vitality" => "Vitality",
	"WaterResistance" => "WaterResistance"
}

$COMP_FUNC_TABLE =
{
	"Lowest" => "Lowest",
	"Highest" => "Highest"
}
