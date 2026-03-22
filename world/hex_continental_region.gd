class_name ContinentalRegion
extends Resource

enum MatchMode { CONTINENTALNESS, ELEVATION }

@export var id:StringName = ""
@export var display_name:String = ""

@export_group("Range")
@export var match_mode: MatchMode = MatchMode.CONTINENTALNESS
@export_range(-1.0,1.0) var start_threshold:float = -1.0
@export_range(-1.0,1.0) var end_threshold:float = 1.0

@export_group("Height")
@export var influence_height:bool = true
@export_range(0.0,1.0) var profile_blend:float = 0.5
@export var height_profile:Curve
@export_range(0.0,1.0) var noise_blend:float = 0.5
@export var height_noise:FastNoiseLite
@export var height_multiplier:float = 1.0

@export_group("Biome")
@export var ignore_climate:bool = false
@export var default_biome:StringName
@export var allowed_biomes:Array[StringName] = []
@export var biome_selection_noise:FastNoiseLite
@export var biome_thresholds:Array[float] = []


func init():
	if not height_profile: height_profile = Curve.new()
	if not height_noise: height_noise = FastNoiseLite.new()
	if not biome_selection_noise: biome_selection_noise = FastNoiseLite.new()


func is_in_range(cntl: float, height: float = 0.0) -> bool:
	match match_mode:
		MatchMode.CONTINENTALNESS:
			return cntl > start_threshold and cntl < end_threshold
		MatchMode.ELEVATION:
			return height > start_threshold and height < end_threshold
	return false



func get_height(x: float, z: float, cntl: float, raw_height: float) -> float:
	if not influence_height:
		return raw_height
	
	var curve_offset := 0.0
	if height_profile:
		var t := clampf(remap(cntl, start_threshold, end_threshold, 0.0, 1.0), 0.0, 1.0)
		curve_offset = lerpf(0.0, height_profile.sample(t), profile_blend)
	
	var noise_offset := 0.0
	if height_noise:
		noise_offset = height_noise.get_noise_2d(x, z) * height_multiplier
	
	return lerpf(raw_height, raw_height + (noise_offset * noise_blend), curve_offset)
	#return raw_height + (curve_offset * profile_blend) + (noise_offset * noise_blend)


func get_biome_at(x: float, z: float, _height: float, climate_biome: StringName) -> StringName:
	# Region doesn't override climate — just pass through
	if not ignore_climate:
		return climate_biome
	
	# Region has its own biome list — select from it
	if allowed_biomes.is_empty():
		return default_biome
	
	if allowed_biomes.size() == 1:
		return allowed_biomes[0]
	
	# Use noise + thresholds to pick from allowed_biomes
	if biome_selection_noise and biome_thresholds.size() >= allowed_biomes.size() - 1:
		var n := biome_selection_noise.get_noise_2d(x, z)
		n = remap(n, -1.0, 1.0, 0.0, 1.0)
		for i in biome_thresholds.size():
			if n < biome_thresholds[i]:
				return allowed_biomes[i]
		return allowed_biomes[allowed_biomes.size() - 1]
	
	return default_biome














	
