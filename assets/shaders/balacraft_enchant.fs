// BalaCraft enchantment glint -- one composite shader for all three enchants (Sharpness /
// Durability / Fortune). Subtle, edge-biased shimmer; colour-coded per enchant; STACKS (a tool
// can show two or three colours at once); intensity scales with tier (I/II/III) but stays low.
//
// Driven through SMODS.Edition (see content/editions/): the card's enchant edition (or a tool's
// inert carrier edition) routes here via Card draw -> Sprite:draw_shader('balacraft_enchant', ...).
//
// Uniforms:
//   enchant        -- send_to_shader vec2: x = animated tilt/time phase, y = G.TIMERS.REAL.
//                     Sent under the shader's original_key ('enchant'); MUST be declared+used.
//   enchant_tiers  -- per-enchant tier 0..3: (sharpness, durability, fortune). Supplied every
//                     frame by SMODS.Shader.send_vars (reads the tool's enchants table, or the
//                     playing card's edition key). See content/editions/enchant_shader.lua.
// All other externs are the standard ones Balatro's Sprite:draw_shader sends to every shader --
// each must stay active (used by dissolve_mask / the vertex tilt), or :send() errors.

#if defined(VERTEX) || __VERSION__ > 100 || defined(GL_FRAGMENT_PRECISION_HIGH)
	#define MY_HIGHP_OR_MEDIUMP highp
#else
	#define MY_HIGHP_OR_MEDIUMP mediump
#endif

extern MY_HIGHP_OR_MEDIUMP vec2 enchant;
extern MY_HIGHP_OR_MEDIUMP vec3 enchant_tiers;

extern MY_HIGHP_OR_MEDIUMP number dissolve;
extern MY_HIGHP_OR_MEDIUMP number time;
extern MY_HIGHP_OR_MEDIUMP vec4 texture_details;
extern MY_HIGHP_OR_MEDIUMP vec2 image_details;
extern bool shadow;
extern MY_HIGHP_OR_MEDIUMP vec4 burn_colour_1;
extern MY_HIGHP_OR_MEDIUMP vec4 burn_colour_2;

// Standard dissolve / shadow / burn handling -- copied verbatim from Balatro's edition shaders so
// destroyed cards dissolve and the drop-shadow pass stays black (no glint bleed onto the shadow).
vec4 dissolve_mask(vec4 tex, vec2 texture_coords, vec2 uv)
{
    if (dissolve < 0.001) {
        return vec4(shadow ? vec3(0.,0.,0.) : tex.xyz, shadow ? tex.a*0.3: tex.a);
    }

    float adjusted_dissolve = (dissolve*dissolve*(3.-2.*dissolve))*1.02 - 0.01; //Adjusting 0.0-1.0 to fall to -0.1 - 1.1 scale so the mask does not pause at extreme values

	float t = time * 10.0 + 2003.;
	vec2 floored_uv = (floor((uv*texture_details.ba)))/max(texture_details.b, texture_details.a);
    vec2 uv_scaled_centered = (floored_uv - 0.5) * 2.3 * max(texture_details.b, texture_details.a);

	vec2 field_part1 = uv_scaled_centered + 50.*vec2(sin(-t / 143.6340), cos(-t / 99.4324));
	vec2 field_part2 = uv_scaled_centered + 50.*vec2(cos( t / 53.1532),  cos( t / 61.4532));
	vec2 field_part3 = uv_scaled_centered + 50.*vec2(sin(-t / 87.53218), sin(-t / 49.0000));

    float field = (1.+ (
        cos(length(field_part1) / 19.483) + sin(length(field_part2) / 33.155) * cos(field_part2.y / 15.73) +
        cos(length(field_part3) / 27.193) * sin(field_part3.x / 21.92) ))/2.;
    vec2 borders = vec2(0.2, 0.8);

    float res = (.5 + .5* cos( (adjusted_dissolve) / 82.612 + ( field + -.5 ) *3.14))
    - (floored_uv.x > borders.y ? (floored_uv.x - borders.y)*(5. + 5.*dissolve) : 0.)*(dissolve)
    - (floored_uv.y > borders.y ? (floored_uv.y - borders.y)*(5. + 5.*dissolve) : 0.)*(dissolve)
    - (floored_uv.x < borders.x ? (borders.x - floored_uv.x)*(5. + 5.*dissolve) : 0.)*(dissolve)
    - (floored_uv.y < borders.x ? (borders.x - floored_uv.y)*(5. + 5.*dissolve) : 0.)*(dissolve);

    if (tex.a > 0.01 && burn_colour_1.a > 0.01 && !shadow && res < adjusted_dissolve + 0.8*(0.5-abs(adjusted_dissolve-0.5)) && res > adjusted_dissolve) {
        if (!shadow && res < adjusted_dissolve + 0.5*(0.5-abs(adjusted_dissolve-0.5)) && res > adjusted_dissolve) {
            tex.rgba = burn_colour_1.rgba;
        } else if (burn_colour_2.a > 0.01) {
            tex.rgba = burn_colour_2.rgba;
        }
    }

    return vec4(shadow ? vec3(0.,0.,0.) : tex.xyz, res > adjusted_dissolve ? (shadow ? tex.a*0.3: tex.a) : .0);
}

// Locked BalaCraft enchant palette (matches the enchant-book tints + tool pips).
const vec3 C_SHARP = vec3(235.0, 150.0,  45.0) / 255.0;  // Sharpness  -> orange
const vec3 C_DURA  = vec3( 80.0, 210.0, 235.0) / 255.0;  // Durability -> cyan
const vec3 C_FORT  = vec3( 70.0, 205.0,  95.0) / 255.0;  // Fortune    -> green

// Minecraft enchantment glint: the shared magenta-violet sheen every enchanted item shows. The
// per-enchant palette above TINTS this base violet (applied HOMOGENEOUSLY over the whole item -- no
// rim layer), so the glint reads orange/cyan/green-ish by enchant while staying Minecraft-purple.
const vec3 C_GLINT = vec3(178.0, 102.0, 240.0) / 255.0;
// (The old rim-biased per-enchant accent layer was removed: it concentrated a bright halo on the
//  card border. Differentiation is now carried by hue-tinting the homogeneous sheen below.)

vec4 effect( vec4 colour, Image texture, vec2 texture_coords, vec2 screen_coords )
{
    vec4 tex = Texel(texture, texture_coords);
    vec2 uv = (((texture_coords)*(image_details)) - texture_details.xy*texture_details.ba)/texture_details.ba;

    // Minecraft-style purple glint: a diagonal twin-band scrolling sheen over the item whenever it
    // holds ANY enchant. HOMOGENEOUS (no rim layer -> no border halo); the per-enchant palette tints
    // the base violet so it still reads which enchant is on.
    number tier_sum = enchant_tiers.x + enchant_tiers.y + enchant_tiers.z;
    if (tier_sum > 0.5) {
        // Per-enchant HUE: tier-weighted blend of the present enchant colours, with the base violet
        // leaning toward it -> stays Minecraft-purple but reads orange-ish (Sharpness) / cyan
        // (Durability) / green (Fortune), or a blend when stacked.
        vec3 ecol = (C_SHARP*enchant_tiers.x + C_DURA*enchant_tiers.y + C_FORT*enchant_tiers.z) / tier_sum;
        vec3 tint = mix(C_GLINT, ecol, 0.45);

        // Diagonal twin-band scrolling sheen (MC's twin glint layers crossing).
        number gt = enchant.y;                                   // real time (G.TIMERS.REAL)
        number b1 = 0.5 + 0.5 * sin((uv.x + uv.y) * 6.2832 - gt * 2.0);
        number b2 = 0.5 + 0.5 * sin((uv.x - uv.y) * 6.2832 + gt * 1.3);
        number sheen = max(pow(b1, 3.0), 0.7 * pow(b2, 3.0));

        // Keep the light card face / nameplate / material / text READABLE. An additive glint blows
        // near-white pixels out to white (that was washing the card out). Fade it as the underlying
        // pixel approaches white, so the violet lives on the actual item art -- like Minecraft -- and
        // the card background stays clean. This also kills the white BORDER halo (the card frame is
        // near-white -> suppressed).
        number luma = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
        number art  = 1.0 - smoothstep(0.68, 0.94, luma);

        // Much lower than the first pass (that wash hid the text): faint base + a low sheen.
        number gi = 0.11 + 0.035 * min(tier_sum, 3.0);
        tex.rgb += tint * (0.035 + sheen * gi) * art * tex.a;
    }

    return dissolve_mask(tex*colour, texture_coords, uv);
}

extern MY_HIGHP_OR_MEDIUMP vec2 mouse_screen_pos;
extern MY_HIGHP_OR_MEDIUMP float hovering;
extern MY_HIGHP_OR_MEDIUMP float screen_scale;

// Vertex tilt -- copied verbatim from Balatro's edition shaders so this glint layer follows the
// card's 3D hover-tilt parallax instead of drifting against it.
#ifdef VERTEX
vec4 position( mat4 transform_projection, vec4 vertex_position )
{
    if (hovering <= 0.){
        return transform_projection * vertex_position;
    }
    float mid_dist = length(vertex_position.xy - 0.5*love_ScreenSize.xy)/length(love_ScreenSize.xy);
    vec2 mouse_offset = (vertex_position.xy - mouse_screen_pos.xy)/screen_scale;
    float scale = 0.2*(-0.03 - 0.3*max(0., 0.3-mid_dist))
                *hovering*(length(mouse_offset)*length(mouse_offset))/(2. -mid_dist);

    return transform_projection * vertex_position + vec4(0,0,0,scale);
}
#endif
