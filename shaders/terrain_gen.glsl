#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// ── Output buffers ────────────────────────────────────────────────────────────
// positions: vec4 per vertex, .w unused
layout(set = 0, binding = 0, std430) restrict writeonly buffer Positions {
	vec4 data[];
} positions;

// colors: vec4 per vertex, .w unused
layout(set = 0, binding = 1, std430) restrict writeonly buffer Colors {
	vec4 data[];
} colors;

// island_centers: one vec4 per island — xy = position, zw = (temp_bias, humid_bias)
layout(set = 0, binding = 2, std430) restrict readonly buffer IslandCenters {
	vec4 data[];
} island_buf;

// ── Push constants ────────────────────────────────────────────────────────────
layout(push_constant, std430) uniform Params {
	int   origin_x;
	int   origin_z;
	int   chunk_size;      // tiles per side (16)
	int   island_count;    // total island centers passed

	float noise_freq;
	float warp_freq;
	float warp_strength;
	int   fbm_octaves;

	float temp_freq;
	int   temp_octaves;
	float temp_altitude_drop;

	float humid_freq;
	int   humid_octaves;

	float threshold_ocean;
	float threshold_beach;
	float threshold_lowland;

	float height_sea_level;
	float height_modifier;

	float island_radius;
	float mask_inner;
	float mask_outer;

	int   elev_seed;
	int   warp_seed;
	int   temp_seed;
	int   humid_seed;

	// river tiles are handled on CPU; this flag just lets us skip the bank color path
	int   river_override_count;  // unused in shader — rivers are baked into river_tiles SSBO

	// biome count (up to 16)
	int   biome_count;
	float vertex_step;
	float river_carve_coast_strength;
	float river_carve_headwater_strength;
	float river_carve_ocean_offset;
	float river_carve_beach_offset;
} p;

// ── Biome table ───────────────────────────────────────────────────────────────
// Each biome: [vec4 0] temp_min, temp_max, humid_min, humid_max
//             [vec4 1] elev_min, elev_max, r, g
//             [vec4 2] b, texture_index (future), color_variation (future), pad
// = 3 vec4s = 12 floats per biome
layout(set = 0, binding = 3, std430) restrict readonly buffer Biomes {
	vec4 data[];  // 3 vec4s per biome = 12 floats
} biome_buf;

// ── River/bank tile sets ──────────────────────────────────────────────────────
// Packed as ivec2 (tile_x, tile_z). Count passed via a leading ivec4(count,0,0,0).
layout(set = 0, binding = 4, std430) restrict readonly buffer RiverTiles {
	ivec4 data[];
} river_buf;

layout(set = 0, binding = 5, std430) restrict readonly buffer BankTiles {
	ivec4 data[];
} bank_buf;

layout(set = 0, binding = 6, std430) restrict readonly buffer GenSettings {
	vec4 data[];
} settings_buf;

// ── Hash / permutation for noise ──────────────────────────────────────────────

uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 0x45d9f3bu;
	x ^= x >> 16u;
	return x;
}

// Value noise with smooth interpolation
float vnoise(float x, float y, uint seed) {
	int ix = int(floor(x));
	int iy = int(floor(y));
	float fx = fract(x);
	float fy = fract(y);
	float ux = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0);
	float uy = fy * fy * fy * (fy * (fy * 6.0 - 15.0) + 10.0);

	uint s = seed;
	float v00 = float(int(hash_u(uint(ix)   + hash_u(uint(iy)   + s)))) / 2147483647.0;
	float v10 = float(int(hash_u(uint(ix+1) + hash_u(uint(iy)   + s)))) / 2147483647.0;
	float v01 = float(int(hash_u(uint(ix)   + hash_u(uint(iy+1) + s)))) / 2147483647.0;
	float v11 = float(int(hash_u(uint(ix+1) + hash_u(uint(iy+1) + s)))) / 2147483647.0;

	return mix(mix(v00, v10, ux), mix(v01, v11, ux), uy);
}

float fbm(float x, float y, uint seed, int octaves) {
	float value    = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < octaves; i++) {
		value     += vnoise(x * frequency, y * frequency, seed + uint(i * 7)) * amplitude;
		frequency *= 2.0;
		amplitude *= 0.5;
	}
	// Match CPU _fbm: accumulate [-1,1] noise, remap once to [0,1] at the end.
	// (A plain clamp zeroed the negative half → almost everything below the
	// ocean threshold.)
	return clamp((value + 1.0) * 0.5, 0.0, 1.0);
}

// ── Island sampling (mask + climate bias) ────────────────────────────────────

struct IslandSample {
	float mask;           // strongest island mask at this coord (0..1)
	vec2  climate_bias;   // mask-weighted average of nearby island climates (temp, humid)
};

IslandSample sample_islands(vec2 coord) {
	float mask_exp = max(settings_buf.data[2].y, 0.05);
	float shape_rotation = settings_buf.data[3].x;
	float radial_wave_count = settings_buf.data[3].y;
	float radial_wave_strength = settings_buf.data[3].z;
	float edge_noise_freq = settings_buf.data[3].w;
	int edge_noise_octaves = max(1, int(settings_buf.data[4].x + 0.5));
	float edge_noise_strength = settings_buf.data[4].y;
	float climate_falloff = max(settings_buf.data[4].z, 0.05);

	float best = 0.0;
	vec2  climate_sum = vec2(0.0);
	float weight_sum  = 0.0;

	for (int i = 0; i < p.island_count; i++) {
		vec4 packed  = island_buf.data[i];
		vec2 center  = packed.xy;
		vec2 climate = packed.zw;

		vec2 off = coord - center;
		float dist = length(off);
		vec2 dir = dist > 0.0001 ? off / dist : vec2(1.0, 0.0);
		float angle = atan(dir.y, dir.x) + shape_rotation;
		float radial_wave = sin(angle * radial_wave_count) * radial_wave_strength;

		float edge_noise = 0.0;
		if (edge_noise_strength > 0.0 && edge_noise_freq > 0.0) {
			edge_noise = (fbm(coord.x * edge_noise_freq + 311.0, coord.y * edge_noise_freq - 177.0, uint(p.warp_seed + 13), edge_noise_octaves) * 2.0 - 1.0) * edge_noise_strength;
		}

		float shape_scale = max(0.2, 1.0 + radial_wave + edge_noise);
		float t = dist / max(p.island_radius * shape_scale, 0.0001);
		float mask = pow(clamp(1.0 - smoothstep(p.mask_inner, p.mask_outer, t), 0.0, 1.0), mask_exp);
		best = max(best, clamp(mask, 0.0, 1.0));

		float w = pow(mask, climate_falloff);
		climate_sum += climate * w;
		weight_sum  += w;
	}

	IslandSample s;
	s.mask = best;
	s.climate_bias = weight_sum > 0.0001 ? climate_sum / weight_sum : vec2(0.5);
	return s;
}

// ── Biome color lookup ────────────────────────────────────────────────────────

vec3 biome_color(float temp, float humid, float elev) {
	for (int i = 0; i < p.biome_count; i++) {
		// 3 vec4s per biome
		vec4 a = biome_buf.data[i * 3 + 0]; // temp_min, temp_max, humid_min, humid_max
		vec4 b = biome_buf.data[i * 3 + 1]; // elev_min, elev_max, r, g
		vec4 c = biome_buf.data[i * 3 + 2]; // b, pad, pad, pad

		float temp_min  = a.x; float temp_max  = a.y;
		float humid_min = a.z; float humid_max  = a.w;
		float elev_min  = b.x; float elev_max  = b.y;
		vec3  col       = vec3(b.z, b.w, c.x);

		if (temp  >= temp_min  && temp  < temp_max  &&
			humid >= humid_min && humid < humid_max  &&
			elev  >= elev_min  && elev  < elev_max) {
			return col;
		}
	}
	return vec3(1.0, 0.0, 1.0); // magenta = unmatched
}

// ── Tile set lookups ──────────────────────────────────────────────────────────
// Format: data[0].x = count; entries packed two per ivec4 starting at data[1]

bool in_river_set(ivec2 coord) {
	int count = river_buf.data[0].x;
	for (int i = 0; i < count; i++) {
		int vi   = 1 + i / 2;
		ivec4 v  = river_buf.data[vi];
		ivec2 tc = (i % 2 == 0) ? v.xy : v.zw;
		if (tc == coord) return true;
	}
	return false;
}

bool in_bank_set(ivec2 coord) {
	int count = bank_buf.data[0].x;
	for (int i = 0; i < count; i++) {
		int vi   = 1 + i / 2;
		ivec4 v  = bank_buf.data[vi];
		ivec2 tc = (i % 2 == 0) ? v.xy : v.zw;
		if (tc == coord) return true;
	}
	return false;
}

// ── Main ──────────────────────────────────────────────────────────────────────

void main() {
	int vx = int(gl_GlobalInvocationID.x);
	int vz = int(gl_GlobalInvocationID.y);

	int verts = p.chunk_size + 1;
	if (vx >= verts || vz >= verts) return;

	int idx = vx * verts + vz;

	float wx_coord = float(p.origin_x) + float(vx) * p.vertex_step;
	float wz_coord = float(p.origin_z) + float(vz) * p.vertex_step;
	ivec2 tile_coord = ivec2(int(floor(wx_coord)), int(floor(wz_coord)));
	bool river_tile = in_river_set(tile_coord);
	bool bank_tile = in_bank_set(tile_coord);

	// Domain warp
	int warp_octaves = max(1, int(settings_buf.data[2].x + 0.5));
	float wx = fbm(wx_coord * p.warp_freq,       wz_coord * p.warp_freq,       uint(p.warp_seed),     warp_octaves) * 2.0 - 1.0;
	float wz = fbm(wx_coord * p.warp_freq + 3.7, wz_coord * p.warp_freq + 3.7, uint(p.warp_seed + 1), warp_octaves) * 2.0 - 1.0;
	wx *= p.warp_strength;
	wz *= p.warp_strength;

	// Elevation
	float raw_elev = fbm((wx_coord + wx) * p.noise_freq, (wz_coord + wz) * p.noise_freq,
						 uint(p.elev_seed), p.fbm_octaves);
	IslandSample island = sample_islands(vec2(wx_coord, wz_coord));
	float mask  = island.mask;
	float elev  = mix(0.0, raw_elev, mask);

	if (river_tile) {
		// Softer carving: shallower headwaters, moderate cuts near mouths.
		float river_floor = mix(p.threshold_ocean + p.river_carve_ocean_offset, p.threshold_beach + p.river_carve_beach_offset, clamp(mask, 0.0, 1.0));
		float carve_target = min(elev, river_floor);
		float carve_strength = mix(p.river_carve_coast_strength, p.river_carve_headwater_strength, clamp(mask, 0.0, 1.0));
		elev = mix(elev, carve_target, carve_strength);
	} else if (bank_tile && elev >= p.threshold_beach) {
		float bank_target = min(elev, p.threshold_beach + 0.05);
		elev = mix(elev, bank_target, 0.25);
	}

	float world_y;
	if (elev < p.threshold_ocean) {
		world_y = 0.0;
	} else {
		float flatten_power = settings_buf.data[0].x;
		float mountain_start_floor = settings_buf.data[0].y;
		float mountain_end = settings_buf.data[0].z;
		float mountain_power = settings_buf.data[0].w;
		float mountain_strength = settings_buf.data[1].x;
		float terrace_steps = max(settings_buf.data[1].y, 1.0);
		float terrace_blend_strength = settings_buf.data[1].z;

		float land = clamp((elev - p.height_sea_level) / max(1.0 - p.height_sea_level, 0.0001), 0.0, 1.0);
		float flattened = pow(land, flatten_power);
		float mountain_start = max(p.threshold_lowland, mountain_start_floor);
		float mountain_mask = smoothstep(mountain_start, mountain_end, land);
		float mountain_boost = mountain_mask * pow(land, mountain_power) * mountain_strength;
		float shaped = clamp(flattened + mountain_boost, 0.0, 1.0);

		float terraced = floor(shaped * terrace_steps) / terrace_steps;
		float terrace_blend = terrace_blend_strength * (1.0 - mountain_mask);
		shaped = mix(shaped, terraced, terrace_blend);

		world_y = shaped * p.height_modifier;
	}

	positions.data[idx] = vec4(wx_coord, world_y, wz_coord, 0.0);

	// Color
	vec3 col;

	if (river_tile) {
		vec3 deep = vec3(0.10, 0.45, 0.90);
		vec3 headwater = vec3(0.18, 0.56, 0.66);
		col = mix(deep, headwater, clamp(mask, 0.0, 1.0) * 0.65);
	} else if (elev < p.threshold_ocean) {
		col = vec3(0.05, 0.20, 0.55);
	} else if (bank_tile && elev >= p.threshold_beach) {
		col = mix(vec3(0.85, 0.80, 0.55), vec3(0.35, 0.65, 0.20), 0.22);
	} else if (elev < p.threshold_beach) {
		col = vec3(0.85, 0.80, 0.55);
	} else {
		float temp  = fbm(wx_coord * p.temp_freq,  wz_coord * p.temp_freq,
						  uint(p.temp_seed), p.temp_octaves);
		float humid = fbm(wx_coord * p.humid_freq, wz_coord * p.humid_freq,
						  uint(p.humid_seed), p.humid_octaves);

		// Blend FBM noise toward this island's climate personality.
		// Effective influence fades to zero at the coast so the transition is smooth.
		float climate_influence = settings_buf.data[4].w;
		float eff = clamp(climate_influence * island.mask, 0.0, 1.0);
		temp  = mix(temp,  island.climate_bias.x, eff);
		humid = mix(humid, island.climate_bias.y, eff);

		temp = clamp(temp - (elev * p.temp_altitude_drop), 0.0, 1.0);

		float t = temp;
		if (elev >= p.threshold_lowland) {
			t = clamp(t - settings_buf.data[1].w, 0.0, 1.0);
		}

		col = biome_color(t, humid, elev);
	}

	colors.data[idx] = vec4(col, 1.0);
}
