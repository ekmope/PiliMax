#include <flutter/runtime_effect.glsl>

// The first float uniform is reserved for the filter input size by Flutter.
uniform vec2 u_size;

// Normalized displacement relative to the shorter filter dimension.
uniform float u_refraction_amount;
// Inset distance as a fraction of the shorter filter dimension.
uniform float u_refraction_height;
// Optional channel separation, also normalized to the shorter dimension.
uniform float u_chromatic_aberration;
// Rounded-corner radius as a fraction of the shorter dimension.
uniform float u_lens_radius;
// Lens center in normalized filter coordinates.
uniform vec2 u_center;

// The first sampler is populated with the input of ImageFilter.shader.
uniform sampler2D u_texture;

out vec4 frag_color;

float rounded_box_sdf(vec2 point, vec2 half_size, float radius) {
  vec2 q = abs(point) - (half_size - vec2(radius));
  float outside = length(max(q, vec2(0.0))) - radius;
  float inside = min(max(q.x, q.y), 0.0);
  return outside + inside;
}

vec2 rounded_box_gradient(vec2 point, vec2 half_size, float radius) {
  vec2 q = abs(point) - (half_size - vec2(radius));
  vec2 point_sign = vec2(
      point.x < 0.0 ? -1.0 : 1.0,
      point.y < 0.0 ? -1.0 : 1.0);
  if (q.x >= 0.0 || q.y >= 0.0) {
    vec2 outside = max(q, vec2(0.0));
    float outside_length = length(outside);
    return outside_length > 0.0001
        ? point_sign * outside / outside_length
        : vec2(0.0);
  }
  float use_x = step(q.y, q.x);
  return point_sign * vec2(use_x, 1.0 - use_x);
}

float circle_map(float value) {
  return 1.0 - sqrt(max(0.0, 1.0 - value * value));
}

void main() {
  vec2 filter_size = max(u_size, vec2(1.0));
  vec2 pixel = FlutterFragCoord().xy;
  vec2 center = u_center * filter_size;
  vec2 half_size = filter_size * 0.5;
  float short_dimension = min(filter_size.x, filter_size.y);
  float radius = min(
      u_lens_radius * short_dimension,
      min(half_size.x, half_size.y));
  float distance_to_edge = rounded_box_sdf(pixel - center, half_size, radius);

  // The clip around the bar normally removes outside pixels. Keeping this
  // factor bounded makes the shader safe when the filter bounds are larger.
  float edge_width = max(u_refraction_height * short_dimension, 1.0);
  float edge_depth = distance_to_edge <= 0.0
      ? clamp(-distance_to_edge / edge_width, 0.0, 1.0)
      : 1.0;
  // Match AndroidLiquidGlass' circle-map lens profile: displacement is
  // strongest at the boundary and falls off smoothly toward the center.
  float edge_factor = distance_to_edge <= 0.0
      ? circle_map(1.0 - edge_depth)
      : 0.0;

  float gradient_radius = min(radius * 1.5, min(half_size.x, half_size.y));
  vec2 geometric_normal = rounded_box_gradient(
    pixel - center,
    half_size,
    gradient_radius);
  vec2 centered = pixel - center;
  float centered_length = length(centered);
  vec2 radial_normal = centered_length > 0.0001
      ? centered / centered_length
      : vec2(0.0);
  // A small depth term avoids a flat-looking capsule while keeping the
  // rounded-rectangle SDF as the dominant normal.
  vec2 normal_input = geometric_normal + 0.18 * radial_normal;
  float normal_length = length(normal_input);
  vec2 normal = normal_length > 0.0001
      ? normal_input / normal_length
      : vec2(0.0, -1.0);

  vec2 refraction_uv =
      normal * (u_refraction_amount * short_dimension * edge_factor) /
      filter_size;
  vec2 chromatic_uv =
      normal * (u_chromatic_aberration * short_dimension * edge_factor) /
      filter_size;

  vec2 uv = pixel / filter_size;
  // Runtime-effect texture coordinates need a vertical flip on GLES.
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
  chromatic_uv.y = -chromatic_uv.y;
  refraction_uv.y = -refraction_uv.y;
#endif
  uv = clamp(uv, vec2(0.0), vec2(1.0));

  vec4 center_sample = texture(u_texture, clamp(uv + refraction_uv, vec2(0.0), vec2(1.0)));
  vec4 red_sample = texture(u_texture, clamp(uv + refraction_uv + chromatic_uv, vec2(0.0), vec2(1.0)));
  vec4 blue_sample = texture(u_texture, clamp(uv + refraction_uv - chromatic_uv, vec2(0.0), vec2(1.0)));

  vec3 color = vec3(red_sample.r, center_sample.g, blue_sample.b);
  // Keep the bevel subtle so content remains readable on both video and
  // static backgrounds. This is the same two-sided light idea as the
  // reference shader, expressed with a fixed normalized light direction.
  vec2 light_direction = normalize(vec2(-0.45, -0.65));
  float light = clamp(dot(normal, light_direction), 0.0, 1.0);
  float shadow = clamp(dot(normal, -light_direction), 0.0, 1.0);
  color *= 1.0 + 0.16 * edge_factor * light;
  color *= 1.0 - 0.06 * edge_factor * shadow;

  frag_color = vec4(color, center_sample.a);
}
